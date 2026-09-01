#!/usr/bin/env bash
#
# Streams Spotify Connect audio to icecast via ffmpeg.
#
# Three backend modes:
#   alsa (default) - uses snd-aloop for real-time pacing. Prevents track skipping.
#   subprocess     - librespot spawns ffmpeg per track. Simpler but may skip.
#   pipe           - continuous pipe via FIFO. Legacy fallback.
#
set -uo pipefail

DEVICE_NAME="${DEVICE_NAME:-Stream Output}"
MOUNT_POINT="${MOUNT_POINT:-stream.mp3}"
ICECAST_HOST="${ICECAST_HOST:-icecast}"
ICECAST_PORT="${ICECAST_PORT:-8000}"
BACKEND="${BACKEND:-alsa}"
BITRATE="${MP3_BITRATE:-192k}"
CACHE_DIR="${CACHE_DIR:-/tmp/spot-cache}"
ALSA_LOOPBACK_OUT="${ALSA_LOOPBACK_OUT:-hw:Loopback,0,0}"
ALSA_LOOPBACK_IN="${ALSA_LOOPBACK_IN:-hw:Loopback,1,0}"

mkdir -p "${CACHE_DIR}"

if [ -z "${ICECAST_SOURCE_PASSWORD:-}" ]; then
  echo "entrypoint: ICECAST_SOURCE_PASSWORD is not set, refusing to start" >&2
  exit 1
fi

ICECAST_URL="icecast://source:${ICECAST_SOURCE_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}/${MOUNT_POINT}"

# Base librespot args (shared across all backends)
librespot_base_args=(
  --name "${DEVICE_NAME}"
  --initial-volume 100
  --enable-volume-normalisation
  --cache "${CACHE_DIR}"
  --disable-gapless
)

if [ -n "${SPOTIFY_USERNAME:-}" ] && [ -n "${SPOTIFY_PASSWORD:-}" ]; then
  echo "entrypoint: credentials provided, starting in remote (account login) mode" >&2
  librespot_base_args+=(--username "${SPOTIFY_USERNAME}" --password "${SPOTIFY_PASSWORD}")
else
  echo "entrypoint: no credentials provided, starting in LAN-only zeroconf mode" >&2
fi

if [ -n "${LIBRESPOT_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  librespot_base_args+=(${LIBRESPOT_EXTRA_ARGS})
fi

echo "entrypoint: backend=${BACKEND}, streaming to ${ICECAST_URL}" >&2

# ── ALSA loopback backend (preferred) ───────────────────────────────────────
# Uses snd-aloop to pace audio output at real-time rate. This prevents
# librespot from downloading tracks faster than playback speed, which
# would cause Spotify to think the track finished and skip ahead.
# Requires: sudo modprobe snd-aloop on the host, device shared into container.
run_alsa() {
  echo "entrypoint: using ALSA loopback (${ALSA_LOOPBACK_OUT} -> ${ALSA_LOOPBACK_IN})" >&2

  # Start ffmpeg reading from the loopback capture side in background
  ffmpeg -loglevel warning \
    -f alsa -i "${ALSA_LOOPBACK_IN}" \
    -af aresample=async=1 \
    -f mp3 -b:a "${BITRATE}" \
    -flush_packets 1 \
    -content_type audio/mpeg \
    "${ICECAST_URL}" &
  FFMPEG_PID=$!

  # Start librespot writing to the loopback playback side (real-time paced)
  librespot "${librespot_base_args[@]}" \
    --backend alsa \
    --device "${ALSA_LOOPBACK_OUT}" \
    --format S16

  # If librespot exits, clean up ffmpeg
  kill "${FFMPEG_PID}" 2>/dev/null || true
  wait "${FFMPEG_PID}" 2>/dev/null || true
}

# ── Subprocess backend ──────────────────────────────────────────────────────
# librespot manages ffmpeg's lifecycle per track. May still skip if
# librespot consumes data faster than real-time.
run_subprocess() {
  FFMPEG_CMD="ffmpeg -loglevel warning -f s16le -ar 44100 -ac 2 -i pipe:0 -af aresample=async=1 -f mp3 -b:a ${BITRATE} -flush_packets 1 -content_type audio/mpeg ${ICECAST_URL}"
  librespot "${librespot_base_args[@]}" \
    --backend subprocess \
    --device "${FFMPEG_CMD}"
}

# ── Pipe backend (legacy fallback) ──────────────────────────────────────────
run_pipe() {
  FIFO="/tmp/librespot-fifo"
  rm -f "${FIFO}"
  mkfifo "${FIFO}"

  ffmpeg -loglevel warning \
    -f s16le -ar 44100 -ac 2 -i "${FIFO}" \
    -af aresample=async=1 \
    -f mp3 -b:a "${BITRATE}" \
    -flush_packets 1 \
    -content_type audio/mpeg \
    "${ICECAST_URL}" &
  FFMPEG_PID=$!

  librespot "${librespot_base_args[@]}" \
    --backend pipe \
    > "${FIFO}"

  kill "${FFMPEG_PID}" 2>/dev/null || true
  wait "${FFMPEG_PID}" 2>/dev/null || true
  rm -f "${FIFO}"
}

# Restart loop
while true; do
  case "${BACKEND}" in
    alsa)       run_alsa ;;
    subprocess) run_subprocess ;;
    pipe)       run_pipe ;;
    *)
      echo "entrypoint: unknown backend '${BACKEND}', falling back to alsa" >&2
      run_alsa
      ;;
  esac

  echo "entrypoint: pipeline exited, restarting in 3s..." >&2
  sleep 3
done
