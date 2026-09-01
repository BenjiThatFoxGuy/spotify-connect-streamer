#!/usr/bin/env bash
#
# Pipes librespot's raw PCM output into ffmpeg, which encodes it to MP3 and
# pushes it into icecast as a live source.
#
# Uses the subprocess backend by default (handles track transitions cleanly)
# with a FIFO fallback for the pipe backend.
#
set -uo pipefail

DEVICE_NAME="${DEVICE_NAME:-Stream Output}"
MOUNT_POINT="${MOUNT_POINT:-stream.mp3}"
ICECAST_HOST="${ICECAST_HOST:-icecast}"
ICECAST_PORT="${ICECAST_PORT:-8000}"
BACKEND="${BACKEND:-subprocess}"
BITRATE="${MP3_BITRATE:-192k}"

if [ -z "${ICECAST_SOURCE_PASSWORD:-}" ]; then
  echo "entrypoint: ICECAST_SOURCE_PASSWORD is not set, refusing to start" >&2
  exit 1
fi

ICECAST_URL="icecast://source:${ICECAST_SOURCE_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}/${MOUNT_POINT}"

# Build the base librespot argument list.
librespot_base_args=(
  --name "${DEVICE_NAME}"
  --initial-volume 100
  --enable-volume-normalisation
)

if [ -n "${SPOTIFY_USERNAME:-}" ] && [ -n "${SPOTIFY_PASSWORD:-}" ]; then
  echo "entrypoint: credentials provided, starting in remote (account login) mode" >&2
  librespot_base_args+=(--username "${SPOTIFY_USERNAME}" --password "${SPOTIFY_PASSWORD}")
else
  echo "entrypoint: no credentials provided, starting in LAN-only zeroconf mode" >&2
fi

# Extra librespot flags, e.g. LIBRESPOT_EXTRA_ARGS="--bitrate 320"
if [ -n "${LIBRESPOT_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  librespot_base_args+=(${LIBRESPOT_EXTRA_ARGS})
fi

echo "entrypoint: backend=${BACKEND}, streaming to ${ICECAST_URL}" >&2

# ── Subprocess backend (preferred) ──────────────────────────────────────────
# librespot manages ffmpeg's lifecycle per track. Track transitions are clean
# because librespot spawns a new ffmpeg process for each track rather than
# keeping a continuous pipe. This prevents ffmpeg buffer stalls from blocking
# Connect transport controls (play/pause/skip).
run_subprocess() {
  FFMPEG_CMD="ffmpeg -loglevel warning -f s16le -ar 44100 -ac 2 -i pipe:0 -af aresample=async=1 -f mp3 -b:a ${BITRATE} -flush_packets 1 -content_type audio/mpeg ${ICECAST_URL}"
  librespot "${librespot_base_args[@]}" \
    --backend subprocess \
    --subprocess-cmd "${FFMPEG_CMD}"
}

# ── Pipe backend (fallback) ─────────────────────────────────────────────────
# Continuous pipe from librespot to ffmpeg via a FIFO. Less clean on track
# transitions but works if subprocess backend has issues. Uses async
# resampling and flush to minimize blocking.
run_pipe() {
  FIFO="/tmp/librespot-fifo"
  rm -f "${FIFO}"
  mkfifo "${FIFO}"

  # Start ffmpeg reading from FIFO in background
  ffmpeg -loglevel warning \
    -f s16le -ar 44100 -ac 2 -i "${FIFO}" \
    -af aresample=async=1 \
    -f mp3 -b:a "${BITRATE}" \
    -flush_packets 1 \
    -content_type audio/mpeg \
    "${ICECAST_URL}" &
  FFMPEG_PID=$!

  # Start librespot writing to FIFO
  librespot "${librespot_base_args[@]}" \
    --backend pipe \
    > "${FIFO}"

  # If librespot exits, clean up ffmpeg
  kill "${FFMPEG_PID}" 2>/dev/null || true
  wait "${FFMPEG_PID}" 2>/dev/null || true
  rm -f "${FIFO}"
}

# Restart loop - bring the device back if the pipeline ever dies
while true; do
  if [ "${BACKEND}" = "subprocess" ]; then
    run_subprocess
  else
    run_pipe
  fi

  echo "entrypoint: pipeline exited, restarting in 3s..." >&2
  sleep 3
done
