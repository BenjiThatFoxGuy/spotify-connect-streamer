#!/usr/bin/env bash
#
# librespot --onevent handler. Updates icecast stream metadata when
# the track changes. Called by librespot with environment variables:
#   PLAYER_EVENT, NAME, ARTISTS, ALBUM, URI, DURATION_MS, etc.
#

ICECAST_HOST="${ICECAST_HOST:-icecast}"
ICECAST_PORT="${ICECAST_PORT:-8000}"
ICECAST_ADMIN_PASSWORD="${ICECAST_ADMIN_PASSWORD:-${ICECAST_SOURCE_PASSWORD:-hackme}}"
MOUNT_POINT="${MOUNT_POINT:-stream.mp3}"

case "${PLAYER_EVENT}" in
  track_changed)
    # Build "Artist - Title" string
    ARTISTS_ONELINE=$(echo "${ARTISTS:-}" | tr '\n' ', ' | sed 's/, $//')
    if [ -n "${ARTISTS_ONELINE}" ]; then
      SONG="${ARTISTS_ONELINE} - ${NAME:-Unknown}"
    else
      SONG="${NAME:-Unknown}"
    fi

    # Update icecast metadata via admin API
    ENCODED_SONG=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${SONG}'))" 2>/dev/null \
      || echo "${SONG}" | sed 's/ /%20/g; s/&/%26/g')

    curl -s -o /dev/null \
      "http://admin:${ICECAST_ADMIN_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}/admin/metadata?mount=/${MOUNT_POINT}&mode=updinfo&song=${ENCODED_SONG}" \
      2>/dev/null || true

    echo "metadata: now playing: ${SONG}" >&2

    # Also write JSON metadata file for other consumers
    METADATA_DIR="${CACHE_DIR:-/tmp/spot-cache}"
    cat > "${METADATA_DIR}/metadata.json" <<METAEOF
{
  "event": "${PLAYER_EVENT}",
  "name": "${NAME:-}",
  "artists": "${ARTISTS_ONELINE}",
  "album": "${ALBUM:-}",
  "uri": "${URI:-}",
  "duration_ms": "${DURATION_MS:-}",
  "track_id": "${TRACK_ID:-}",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
METAEOF
    ;;

  playing|paused|stopped)
    # Log state changes
    echo "metadata: ${PLAYER_EVENT} (track: ${TRACK_ID:-unknown})" >&2
    ;;
esac
