#!/usr/bin/env bash
#
# Pipes librespot's raw PCM output straight into ffmpeg, which encodes it to
# MP3 and pushes it into icecast as a live source.
#
#   librespot (pipe backend) -> stdout -> ffmpeg (s16le PCM -> MP3) -> icecast
#
set -uo pipefail

DEVICE_NAME="${DEVICE_NAME:-Stream Output}"
MOUNT_POINT="${MOUNT_POINT:-stream.mp3}"
ICECAST_HOST="${ICECAST_HOST:-icecast}"
ICECAST_PORT="${ICECAST_PORT:-8000}"

if [ -z "${ICECAST_SOURCE_PASSWORD:-}" ]; then
  echo "entrypoint: ICECAST_SOURCE_PASSWORD is not set, refusing to start" >&2
  exit 1
fi

# Build the librespot argument list. Credentials (remote mode) are only
# added when both SPOTIFY_USERNAME and SPOTIFY_PASSWORD are provided.
# Otherwise librespot falls back to zeroconf discovery, which only
# advertises the device on the local network (LAN-only, no credentials
# stored or transmitted).
librespot_args=(
  --name "${DEVICE_NAME}"
  --backend pipe
  --initial-volume 100
  --enable-volume-normalisation
)

if [ -n "${SPOTIFY_USERNAME:-}" ] && [ -n "${SPOTIFY_PASSWORD:-}" ]; then
  echo "entrypoint: credentials provided, starting in remote (account login) mode" >&2
  librespot_args+=(--username "${SPOTIFY_USERNAME}" --password "${SPOTIFY_PASSWORD}")
else
  echo "entrypoint: no credentials provided, starting in LAN-only zeroconf mode" >&2
fi

# Any extra librespot flags the caller wants, e.g. LIBRESPOT_EXTRA_ARGS="--bitrate 320"
if [ -n "${LIBRESPOT_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  librespot_args+=(${LIBRESPOT_EXTRA_ARGS})
fi

ICECAST_URL="icecast://source:${ICECAST_SOURCE_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}/${MOUNT_POINT}"

echo "entrypoint: streaming to ${ICECAST_URL}" >&2

# Restart the pipeline if it ever dies (session ends, network hiccup, etc.)
# so the Connect device comes back instead of staying dead in the container.
while true; do
  librespot "${librespot_args[@]}" \
    | ffmpeg -loglevel warning \
      -f s16le -ar 44100 -ac 2 -i pipe:0 \
      -f mp3 -b:a 192k -content_type audio/mpeg \
      "${ICECAST_URL}"

  echo "entrypoint: pipeline exited, restarting in 3s..." >&2
  sleep 3
done
