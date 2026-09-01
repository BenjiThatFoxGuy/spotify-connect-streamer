# spotify-connect-streamer

A proof-of-concept that turns Spotify Connect audio into a plain HTTP MP3
stream, so anything that can play an internet radio URL can play whatever
you cast to it from Spotify.

```
Spotify App -> librespot (Connect device) -> raw PCM pipe -> ffmpeg (MP3 encode) -> icecast2 -> HTTP stream
```

- **librespot** presents itself as a Spotify Connect device and outputs the
  raw decoded audio (16-bit PCM, 44.1kHz, stereo) instead of playing it
  through a sound card.
- **ffmpeg** reads that raw PCM straight from the pipe and encodes it to
  MP3 in real time.
- **icecast2** receives the MP3 as a live source and serves it to any
  number of HTTP listeners.

This is a POC: it works, but it hasn't been hardened for production use
(no TLS, default-ish passwords, no auth on the listener side, etc).

## Quick start

```bash
cp .env.example .env
# edit .env if you want, defaults work for a first try

docker compose up --build
```

Once it's running:

- The Connect device ("Stream Output" by default) shows up in the Spotify
  app's device picker on any device on the same LAN.
- Cast something to it.
- Open `http://<host>:8000/stream.mp3` in a browser, VLC, or any HTTP
  audio player to hear it.
- Icecast's status page is at `http://<host>:8000/`.

## Configuration

All configuration is via environment variables, set in `.env` (copy
`.env.example` to `.env` and edit) or exported before running
`docker compose up`.

| Variable                   | Default         | Meaning                                              |
|-----------------------------|-----------------|-------------------------------------------------------|
| `DEVICE_NAME`               | `Stream Output` | Name shown in the Spotify Connect device picker       |
| `ICECAST_SOURCE_PASSWORD`   | `hackme`        | Password the streamer uses to push audio into icecast |
| `ICECAST_ADMIN_PASSWORD`    | `hackme`        | Password for icecast's `/admin` web UI                |
| `ICECAST_RELAY_PASSWORD`    | `hackme`        | Required by icecast, unused in this POC               |
| `MOUNT_POINT`                | `stream.mp3`    | Path the stream is published under (`/stream.mp3`)    |
| `LIBRESPOT_EXTRA_ARGS`      | (empty)         | Extra flags passed straight through to librespot       |
| `SPOTIFY_USERNAME`          | (unset)         | See "Dual mode" below                                 |
| `SPOTIFY_PASSWORD`          | (unset)         | See "Dual mode" below                                 |

Change the default passwords before exposing port 8000 beyond your own
machine — the icecast admin UI and source password are the only things
gatekeeping this stack.

## Dual mode: LAN vs remote

This stack can run in two modes, chosen automatically based on whether
Spotify credentials are set:

- **LAN mode (default, safer)** — leave `SPOTIFY_USERNAME` /
  `SPOTIFY_PASSWORD` unset in `.env`. librespot advertises itself via
  zeroconf (mDNS) and only shows up as a Connect target for Spotify apps on
  the same local network. No account credentials are stored or sent
  anywhere.

- **Remote mode** — set both `SPOTIFY_USERNAME` and `SPOTIFY_PASSWORD` in
  `.env`. librespot logs in with that account directly, so the device
  shows up as a Connect target wherever that account is signed in, not
  just on the LAN. This means the account credentials live in your `.env`
  file and inside the running container's environment, so treat that file
  accordingly (it's already gitignored).

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
  (mDNS) discovery works and the Connect device is actually visible on
  your LAN. If you only ever use remote (credential) mode, you can switch
  it back to normal bridge networking.
- librespot is built from the `dev` branch of
  [librespot-org/librespot](https://github.com/librespot-org/librespot) at
  image build time, for the latest Spotify Connect protocol fixes. Rebuild
  the `streamer` image (`docker compose build --no-cache streamer`)
  periodically to pick up upstream changes.
- If the pipeline dies for any reason (session ends, network hiccup), the
  container restarts it automatically after a few seconds rather than
  exiting.
