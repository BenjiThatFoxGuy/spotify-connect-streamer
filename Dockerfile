# --- Stage 1: build librespot from the dev branch ---
# We build from source (rather than pulling a prebuilt binary) because the
# dev branch tracks the latest Spotify Connect protocol fixes, and the
# "pipe" playback backend we need is always compiled in (it's not gated
# behind a Cargo feature), so a plain build gets us what we want.
FROM rust:1-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    pkg-config \
    cmake \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Shallow-clone the dev branch to keep the build fast.
RUN git clone --depth 1 --branch dev https://github.com/librespot-org/librespot.git .

# Build with rustls (no system OpenSSL needed) and pure-Rust mDNS
# (no Avahi needed) so the build stays free of extra system deps.
# The "pipe" backend used at runtime is always included, no feature flag
# required.
RUN cargo build --release \
    --no-default-features \
    --features "rustls-tls-webpki-roots with-libmdns"

# --- Stage 2: slim runtime image ---
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/librespot /usr/local/bin/librespot

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
