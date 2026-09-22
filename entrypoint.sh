#!/usr/bin/env bash
set -uo pipefail

DEVICE_NAME="${DEVICE_NAME:-Stream Output}"
DEVICE_TYPE="${DEVICE_TYPE:-speaker}"
MOUNT_POINT="${MOUNT_POINT:-stream.mp3}"
ICECAST_HOST="${ICECAST_HOST:-icecast}"
ICECAST_PORT="${ICECAST_PORT:-8000}"
ICECAST_SOURCE_USERNAME="${ICECAST_SOURCE_USERNAME:-source}"
BITRATE="${MP3_BITRATE:-320k}"
CACHE_DIR="${CACHE_DIR:-/tmp/spot-cache}"
CONFIG_DIR="${GO_LIBRESPOT_CONFIG_DIR:-${CACHE_DIR}/go-librespot}"
FIFO="${AUDIO_FIFO:-/tmp/go-librespot-audio.fifo}"
API_HOST="${GO_LIBRESPOT_API_HOST:-127.0.0.1}"
API_BIND_ADDRESS="${GO_LIBRESPOT_API_BIND_ADDRESS:-0.0.0.0}"
API_PORT="${GO_LIBRESPOT_API_PORT:-3678}"

mkdir -p "${CACHE_DIR}" "${CONFIG_DIR}"

if [ -z "${ICECAST_SOURCE_PASSWORD:-}" ]; then
  echo "entrypoint: ICECAST_SOURCE_PASSWORD is not set, refusing to start" >&2
  exit 1
fi

case "${BITRATE}" in
  96k|96) GO_BITRATE=96 ;;
  160k|160) GO_BITRATE=160 ;;
  320k|320) GO_BITRATE=320 ;;
  *)
    echo "entrypoint: unsupported MP3_BITRATE='${BITRATE}', use 96k, 160k, or 320k" >&2
    exit 1
    ;;
esac

AUTH_MODE="${AUTH_MODE:-zeroconf}"
case "${AUTH_MODE}" in
  zeroconf) CREDENTIALS_TYPE="zeroconf" ;;
  device-auth|device_auth) CREDENTIALS_TYPE="device_auth" ;;
  oauth|interactive) CREDENTIALS_TYPE="interactive" ;;
  password)
    echo "entrypoint: AUTH_MODE=password is not supported by go-librespot; use device-auth, oauth, or zeroconf" >&2
    exit 1
    ;;
  *)
    echo "entrypoint: unknown AUTH_MODE='${AUTH_MODE}', falling back to zeroconf" >&2
    CREDENTIALS_TYPE="zeroconf"
    ;;
esac

DISABLE_DISCOVERY="${DISABLE_DISCOVERY:-false}"
if [ "${CREDENTIALS_TYPE}" = "zeroconf" ]; then
  ZEROCONF_ENABLED=true
elif [ "${DISABLE_DISCOVERY}" = "true" ]; then
  ZEROCONF_ENABLED=false
else
  ZEROCONF_ENABLED=true
fi

if [ "${DISABLE_DISCOVERY}" = "true" ] && [ "${CREDENTIALS_TYPE}" = "zeroconf" ]; then
  echo "entrypoint: WARNING: DISABLE_DISCOVERY=true is ignored with AUTH_MODE=zeroconf" >&2
fi

export DEVICE_NAME DEVICE_TYPE CONFIG_DIR FIFO API_BIND_ADDRESS API_PORT GO_BITRATE CREDENTIALS_TYPE ZEROCONF_ENABLED CACHE_DIR
export ZEROCONF_BACKEND="${GO_LIBRESPOT_ZEROCONF_BACKEND:-builtin}"
export OAUTH_PORT="${OAUTH_PORT:-8888}"
export PERSIST_ZEROCONF_CREDENTIALS="${PERSIST_ZEROCONF_CREDENTIALS:-false}"
export NORMALISATION_DISABLED="${NORMALISATION_DISABLED:-false}"
export DISABLE_AUTOPLAY="${DISABLE_AUTOPLAY:-false}"
export CROSSFADE_DURATION="${CROSSFADE_DURATION:-0}"
export PREFER_FIREWALL_FRIENDLY_PORTS="${PREFER_FIREWALL_FRIENDLY_PORTS:-false}"

python3 <<'PY'
import json
import os

def env_bool(name):
    return str(os.environ.get(name, "false")).lower() in {"1", "true", "yes", "on"}

def line(key, value, indent=0):
    prefix = " " * indent
    if isinstance(value, bool):
        rendered = "true" if value else "false"
    elif isinstance(value, int):
        rendered = str(value)
    else:
        rendered = json.dumps(value)
    return f"{prefix}{key}: {rendered}"

config_dir = os.environ["CONFIG_DIR"]
credentials_type = os.environ["CREDENTIALS_TYPE"]
lines = [
    line("log_level", os.environ.get("GO_LIBRESPOT_LOG_LEVEL", "info")),
    line("device_name", os.environ["DEVICE_NAME"]),
    line("device_type", os.environ["DEVICE_TYPE"]),
    line("audio_backend", "pipe"),
    line("audio_output_pipe", os.environ["FIFO"]),
    line("audio_output_pipe_format", "s16le"),
    line("audio_output_pipe_wait_for_reader", True),
    line("bitrate", int(os.environ["GO_BITRATE"])),
    line("initial_volume", int(os.environ.get("INITIAL_VOLUME", "100"))),
    line("ignore_last_volume", env_bool("IGNORE_LAST_VOLUME")),
    line("external_volume", env_bool("EXTERNAL_VOLUME")),
    line("normalisation_disabled", env_bool("NORMALISATION_DISABLED")),
    line("disable_autoplay", env_bool("DISABLE_AUTOPLAY")),
    line("crossfade_duration", int(os.environ["CROSSFADE_DURATION"])),
    line("prefer_firewall_friendly_ports", env_bool("PREFER_FIREWALL_FRIENDLY_PORTS")),
    line("zeroconf_enabled", env_bool("ZEROCONF_ENABLED")),
    line("zeroconf_backend", os.environ["ZEROCONF_BACKEND"]),
    "server:",
    line("enabled", True, 2),
    line("address", os.environ["API_BIND_ADDRESS"], 2),
    line("port", int(os.environ["API_PORT"]), 2),
    "cache:",
    line("enabled", True, 2),
    line("dir", os.path.join(os.environ["CACHE_DIR"], "audio-cache"), 2),
    line("size_limit", os.environ.get("GO_LIBRESPOT_CACHE_SIZE", "1GB"), 2),
    "credentials:",
    line("type", credentials_type, 2),
]

if credentials_type == "interactive":
    lines.extend(["  interactive:", line("callback_port", int(os.environ["OAUTH_PORT"]), 4)])
elif credentials_type == "zeroconf":
    lines.extend(["  zeroconf:", line("persist_credentials", env_bool("PERSIST_ZEROCONF_CREDENTIALS"), 4)])
elif credentials_type == "device_auth":
    lines.append("  device_auth: {}")

with open(os.path.join(config_dir, "config.yml"), "w", encoding="utf-8") as config_file:
    config_file.write("\n".join(lines) + "\n")
PY

rm -f "${FIFO}"
mkfifo "${FIFO}"

ICECAST_URL="icecast://${ICECAST_SOURCE_USERNAME}:${ICECAST_SOURCE_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}/${MOUNT_POINT}"
API_URL="http://${API_HOST}:${API_PORT}"

cleanup() {
  trap - INT TERM EXIT
  kill "${GO_LIBRESPOT_PID:-}" "${FFMPEG_PID:-}" "${METADATA_PID:-}" 2>/dev/null || true
  wait "${GO_LIBRESPOT_PID:-}" "${FFMPEG_PID:-}" "${METADATA_PID:-}" 2>/dev/null || true
  rm -f "${FIFO}"
}
trap cleanup INT TERM EXIT

echo "entrypoint: starting go-librespot auth=${AUTH_MODE} bitrate=${GO_BITRATE}kbps config=${CONFIG_DIR}" >&2
go-librespot --config_dir "${CONFIG_DIR}" &
GO_LIBRESPOT_PID=$!

echo "entrypoint: streaming FIFO ${FIFO} to ${ICECAST_URL}" >&2
ffmpeg -loglevel warning \
  -f s16le -ar 44100 -ac 2 -i "${FIFO}" \
  -af aresample=async=1 \
  -f mp3 -b:a "${BITRATE}" \
  -flush_packets 1 \
  -content_type audio/mpeg \
  "${ICECAST_URL}" &
FFMPEG_PID=$!

python3 /app/config/metadata_poller.py &
METADATA_PID=$!

if [ "${CREDENTIALS_TYPE}" = "device_auth" ]; then
  echo "entrypoint: device auth selected; pairing details will be logged and exposed at ${API_URL}/auth/code while pending" >&2
elif [ "${CREDENTIALS_TYPE}" = "interactive" ]; then
  echo "entrypoint: interactive OAuth selected; callback port is ${OAUTH_PORT}" >&2
fi

wait -n "${GO_LIBRESPOT_PID}" "${FFMPEG_PID}" "${METADATA_PID}"
echo "entrypoint: a child process exited, shutting down" >&2
exit 1
