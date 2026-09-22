#!/usr/bin/env python3
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


api_host = os.environ.get("GO_LIBRESPOT_API_HOST", "127.0.0.1")
api_port = os.environ.get("GO_LIBRESPOT_API_PORT", "3678")
status_url = f"http://{api_host}:{api_port}/status"

icecast_host = os.environ.get("ICECAST_HOST", "icecast")
icecast_port = os.environ.get("ICECAST_PORT", "8000")
admin_user = os.environ.get("ICECAST_ADMIN_USER", "admin")
admin_password = os.environ.get("ICECAST_ADMIN_PASSWORD") or os.environ.get("ICECAST_SOURCE_PASSWORD", "hackme")
mount_point = os.environ.get("MOUNT_POINT", "stream.mp3")
metadata_dir = os.environ.get("CACHE_DIR", "/tmp/spot-cache")
poll_interval = float(os.environ.get("METADATA_POLL_INTERVAL", "2"))


def fetch_status():
    try:
        with urllib.request.urlopen(status_url, timeout=2) as response:
            if response.status == 204:
                return None
            return json.load(response)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return None


def update_icecast(song):
    query = urllib.parse.urlencode({"mount": f"/{mount_point}", "mode": "updinfo", "song": song})
    url = f"http://{admin_user}:{admin_password}@{icecast_host}:{icecast_port}/admin/metadata?{query}"
    try:
        urllib.request.urlopen(url, timeout=2).close()
    except (urllib.error.URLError, TimeoutError):
        pass


def write_metadata(track):
    os.makedirs(metadata_dir, exist_ok=True)
    artist_names = track.get("artist_names") or []
    payload = {
        "event": "track_changed",
        "name": track.get("name") or "",
        "artists": ", ".join(artist_names),
        "album": track.get("album_name") or "",
        "uri": track.get("uri") or "",
        "duration_ms": track.get("duration") or "",
        "track_id": (track.get("uri") or "").split(":")[-1],
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    path = os.path.join(metadata_dir, "metadata.json")
    with open(path, "w", encoding="utf-8") as metadata_file:
        json.dump(payload, metadata_file, indent=2)
        metadata_file.write("\n")


def main():
    last_uri = None
    while True:
        status = fetch_status()
        track = status.get("track") if status else None
        uri = track.get("uri") if track else None
        if track and uri and uri != last_uri:
            artist_names = track.get("artist_names") or []
            song = track.get("name") or "Unknown"
            if artist_names:
                song = f"{', '.join(artist_names)} - {song}"
            update_icecast(song)
            write_metadata(track)
            print(f"metadata: now playing: {song}", file=sys.stderr, flush=True)
            last_uri = uri
        time.sleep(poll_interval)


if __name__ == "__main__":
    main()