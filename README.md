# spotify-connect-streamer

Dockerized Spotify Connect to Icecast streaming, using
[go-librespot](https://github.com/devgianlu/go-librespot) so Spotify DJ playback,
including narration, can flow through the same HTTP MP3 stream.

```
Spotify App -> go-librespot (Connect device + DJ support) -> FIFO -> ffmpeg -> Icecast -> HTTP stream
```

`go-librespot` presents itself as a Spotify Connect device and writes decoded
16-bit PCM audio to a named pipe. `ffmpeg` reads that pipe in real time, encodes
MP3, and pushes it into Icecast.

Spotify Premium is expected for Spotify Connect and DJ support.

## Quick start

```bash
cp .env.example .env
# edit .env if you want, defaults work for a first try

docker compose up --build
```

Once it's running:

- The Connect device ("Stream Output" by default) shows up in the Spotify
  app's device picker on any device on the same LAN.
- Cast music, podcasts, or DJ to it.
- Open `http://<host>:8000/stream.mp3` in a browser, VLC, or any HTTP
  audio player to hear it.
- Icecast's status page is at `http://<host>:8000/`.

## Configuration

All configuration is via environment variables, set in `.env` (copy
`.env.example` to `.env` and edit) or exported before running
`docker compose up`.

| Variable                   | Default         | Meaning                                              |
|-----------------------------|-----------------|-------------------------------------------------------|
| `DEVICE_NAME` | `Stream Output` | Name shown in Spotify's device picker |
| `DEVICE_TYPE` | `speaker` | Spotify Connect device icon/type |
| `ICECAST_SOURCE_PASSWORD` | `hackme` | Password the streamer uses to push audio into Icecast |
| `ICECAST_ADMIN_PASSWORD` | `hackme` | Password for Icecast admin metadata updates |
| `ICECAST_RELAY_PASSWORD` | `hackme` | Required by the Icecast image |
| `MOUNT_POINT` | `stream.mp3` | Path the stream is published under (`/stream.mp3`) |
| `MP3_BITRATE` | `320k` | Icecast MP3 bitrate: `96k`, `160k`, or `320k` |
| `AUTH_MODE` | `zeroconf` | `zeroconf`, `device-auth`, or `oauth` |
| `DISABLE_DISCOVERY` | `false` | Disable mDNS after account auth |
| `GO_LIBRESPOT_API_PORT` | `3678` | Local go-librespot API port for metadata polling |
| `GO_LIBRESPOT_ZEROCONF_BACKEND` | `builtin` | `builtin` or `avahi` mDNS registration |
| `OAUTH_PORT` | `8888` | Interactive OAuth callback port |

Change the default passwords before exposing port 8000 beyond your own
machine — the icecast admin UI and source password are the only things
gatekeeping this stack.

## Auth modes

- `zeroconf` keeps the device LAN-discoverable and does not require account
  credentials in environment variables.
- `device-auth` prints a pairing URL/code for spotify.com/pair and stores the
  resulting credentials in the `spot-cache` Docker volume.
- `oauth` starts go-librespot's interactive browser flow using `OAUTH_PORT` as
  the callback port.

The old username/password mode is intentionally gone. go-librespot supports
modern Spotify auth flows instead.

## Metadata

The streamer enables go-librespot's REST API and polls `/status` to update
Icecast metadata on track changes. The latest metadata is also written to
`metadata.json` in the cache volume.

## How to consume the stream

Anything that can open an HTTP audio stream works:

```bash
# mpv / ffplay / vlc
mpv http://<host>:8000/stream.mp3
ffplay http://<host>:8000/stream.mp3
vlc http://<host>:8000/stream.mp3
```

Or point a `<audio>` tag / any internet-radio-capable device at the same
URL.

## Notes

- The `streamer` service runs with `network_mode: host` so that zeroconf
  (mDNS) discovery works and the Connect device is actually visible on your LAN.
- go-librespot is pinned by the `GO_LIBRESPOT_REF` Docker build arg. Rebuild the
  image periodically to pick up upstream Connect and DJ fixes.

```bash
docker build --build-arg GO_LIBRESPOT_REF=v0.10.0 -t spotify-connect-streamer .
```
