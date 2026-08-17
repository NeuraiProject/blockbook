# syntax=docker/dockerfile:1
#
# backend-neurai — Neurai full node (neuraid) packaged for Blockbook.
#
# The image installs the `backend-neurai_<version>-neurai-dev_amd64.deb`
# produced by `make deb-backend-neurai` in this repository. The .deb is taken
# from ../debs/ if present (local build), otherwise it is downloaded from the
# NeuraiProject/blockbook GitHub release.
#
# Build context must be the `docker/` directory (see docker-compose.yml).

ARG BASE_IMAGE=debian:12-slim

# ---------------------------------------------------------------------------
# Stage 1: obtain the .deb (local drop-in or GitHub release)
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS fetch
ARG DEBIAN_FRONTEND=noninteractive
ARG BLOCKBOOK_RELEASE=v0.6.0
ARG BACKEND_VERSION=1.0.6.0
ARG BACKEND_DEB_URL=

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

COPY debs/ /debs/
RUN set -eu; \
    local_deb="$(ls /debs/backend-neurai_*.deb 2>/dev/null | head -n1 || true)"; \
    if [ -n "$local_deb" ]; then \
        echo ">> using local package: $local_deb"; \
        cp "$local_deb" /backend-neurai.deb; \
    else \
        url="${BACKEND_DEB_URL:-https://github.com/NeuraiProject/blockbook/releases/download/${BLOCKBOOK_RELEASE}/backend-neurai_${BACKEND_VERSION}-neurai-dev_amd64.deb}"; \
        echo ">> downloading $url"; \
        curl -fSL --retry 3 --retry-delay 5 -o /backend-neurai.deb "$url"; \
    fi; \
    dpkg-deb --info /backend-neurai.deb | grep -E '^ (Package|Version|Architecture):'

# ---------------------------------------------------------------------------
# Stage 2: runtime image
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE}
ARG DEBIAN_FRONTEND=noninteractive
ARG BACKEND_VERSION=1.0.6.0

LABEL org.opencontainers.image.title="backend-neurai" \
      org.opencontainers.image.description="Neurai full node (neuraid) for Blockbook" \
      org.opencontainers.image.version="${BACKEND_VERSION}" \
      org.opencontainers.image.source="https://github.com/NeuraiProject/blockbook" \
      org.opencontainers.image.vendor="Neurai Project"

# The .deb depends on logrotate; the rest (libc, libstdc++) is already in the base image.
COPY --from=fetch /backend-neurai.deb /tmp/backend-neurai.deb
RUN apt-get update \
 && apt-get install -y --no-install-recommends /tmp/backend-neurai.deb \
 && rm -f /tmp/backend-neurai.deb \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && /opt/coins/nodes/neurai/neuraid --version | head -n1

COPY backend-neurai/entrypoint.sh backend-neurai/healthcheck.sh backend-neurai/neurai-cli /usr/local/bin/
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh /usr/local/bin/neurai-cli

ENV NEURAI_INSTALL_DIR=/opt/coins/nodes/neurai \
    NEURAI_DATA_DIR=/opt/coins/data/neurai/backend \
    NEURAI_RUN_DIR=/run/neurai \
    NEURAI_USER=neurai \
    RPC_BIND=0.0.0.0 \
    RPC_ALLOW_IP="172.16.0.0/12 192.168.0.0/16 10.0.0.0/8" \
    ZMQ_BIND=0.0.0.0 \
    P2P_LISTEN=0

VOLUME ["/opt/coins/data/neurai/backend"]

# 8069 = JSON-RPC, 38369 = ZMQ (both only for the compose network), 19000 = P2P
EXPOSE 8069 38369 19000

HEALTHCHECK --interval=30s --timeout=15s --start-period=15m --retries=5 \
  CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
