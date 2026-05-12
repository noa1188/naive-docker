# syntax=docker/dockerfile:1

FROM --platform=$BUILDPLATFORM golang:1.22-bookworm AS build

WORKDIR /src

ARG TARGETOS
ARG TARGETARCH

RUN set -eux; \
    go version; \
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest; \
    GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" /go/bin/xcaddy build \
      --output /out/caddy \
      --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive \
      --with github.com/caddy-dns/cloudflare

FROM debian:bookworm-slim

ARG BUILD_DATE=""
ARG VCS_REF=""
ARG IMAGE_VERSION=""
ARG NAIVEPROXY_UPSTREAM_VERSION="unknown"

LABEL org.opencontainers.image.title="naiveproxy-docker" \
      org.opencontainers.image.description="Caddy with naive forward proxy and Cloudflare DNS challenge support" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.source="https://github.com/RayWangQvQ/naiveproxy-docker" \
      org.opencontainers.image.naiveproxy.upstream-version="${NAIVEPROXY_UPSTREAM_VERSION}"

RUN set -eux; \
    apt-get update; \
    apt-get install --no-install-recommends -y \
      bash \
      ca-certificates \
      tzdata; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /out/caddy /usr/bin/caddy

RUN set -eux; \
    chmod +x /usr/bin/caddy; \
    caddy version; \
    mkdir -p /config/caddy /data/caddy /app

WORKDIR /app

ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data

EXPOSE 443
EXPOSE 443/udp
EXPOSE 2019

CMD ["bash", "/data/entry.sh"]
