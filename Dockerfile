# --- Stage 1: build librespot from the dev branch ---
FROM rust:1-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    pkg-config \
    cmake \
    libasound2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Shallow-clone the dev branch for latest Connect protocol fixes.
RUN git clone --depth 1 --branch dev https://github.com/librespot-org/librespot.git .

# Build with ALSA backend (for snd-aloop real-time pacing),
# rustls (no system OpenSSL), and pure-Rust mDNS (no Avahi).
# Pipe and subprocess backends are always included.
RUN cargo build --release \
    --no-default-features \
    --features "alsa-backend rustls-tls-webpki-roots with-libmdns"

# --- Stage 2: slim runtime image ---
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    pv \
    ca-certificates \
    libasound2 \
    alsa-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/librespot /usr/local/bin/librespot

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
