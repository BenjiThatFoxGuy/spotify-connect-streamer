# --- Stage 1: build go-librespot ---
FROM alpine:3.23 AS builder

ARG GO_LIBRESPOT_REF=v0.10.0

RUN apk update && apk -U --no-cache add \
    go \
    git \
    alsa-lib-dev \
    libogg-dev \
    libvorbis-dev \
    flac-dev \
    mpg123-dev \
    gcc \
    musl-dev

WORKDIR /src

RUN git clone --depth 1 --branch "${GO_LIBRESPOT_REF}" https://github.com/devgianlu/go-librespot.git .
RUN CGO_ENABLED=1 go build -v -o /usr/local/bin/go-librespot ./cmd/daemon

# --- Stage 2: runtime image ---
FROM alpine:3.23

RUN apk update && apk -U --no-cache add \
    bash \
    ffmpeg \
    curl \
    python3 \
    ca-certificates \
    libpulse \
    avahi \
    libgcc \
    gcompat \
    alsa-lib \
    && rm -rf /var/cache/apk/*

COPY --from=builder /usr/local/bin/go-librespot /usr/local/bin/go-librespot

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY config/ /app/config/
RUN chmod +x /app/config/*.py

ENTRYPOINT ["/entrypoint.sh"]
