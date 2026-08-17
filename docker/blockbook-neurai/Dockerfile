# syntax=docker/dockerfile:1
#
# blockbook-neurai — Blockbook indexer/explorer for Neurai.
#
# The image installs the `blockbook-neurai_<version>_amd64.deb` produced by
# `make deb-blockbook-neurai` in this repository. The .deb is taken from
# ../debs/ if present (local build), otherwise it is downloaded from the
# NeuraiProject/blockbook GitHub release.
#
# NOTE: blockbook 0.6.x is built on debian:12 (glibc 2.36); the runtime base
# image must be debian:12 or newer (ubuntu:22.04 is too old).
#
# Build context must be the `docker/` directory (see docker-compose.yml).

ARG BASE_IMAGE=debian:12-slim

# ---------------------------------------------------------------------------
# Stage 1: obtain the .deb (local drop-in or GitHub release)
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS fetch
ARG DEBIAN_FRONTEND=noninteractive
ARG BLOCKBOOK_RELEASE=v0.6.0
ARG BLOCKBOOK_VERSION=0.6.0
ARG BLOCKBOOK_DEB_URL=

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

COPY debs/ /debs/
RUN set -eu; \
    local_deb="$(ls /debs/blockbook-neurai_*.deb 2>/dev/null | head -n1 || true)"; \
    if [ -n "$local_deb" ]; then \
        echo ">> using local package: $local_deb"; \
        cp "$local_deb" /blockbook-neurai.deb; \
    else \
        url="${BLOCKBOOK_DEB_URL:-https://github.com/NeuraiProject/blockbook/releases/download/${BLOCKBOOK_RELEASE}/blockbook-neurai_${BLOCKBOOK_VERSION}_amd64.deb}"; \
        echo ">> downloading $url"; \
        curl -fSL --retry 3 --retry-delay 5 -o /blockbook-neurai.deb "$url"; \
    fi; \
    dpkg-deb --info /blockbook-neurai.deb | grep -E '^ (Package|Version|Architecture|Depends):'

# ---------------------------------------------------------------------------
# Stage 2: runtime image
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE}
ARG DEBIAN_FRONTEND=noninteractive
ARG BLOCKBOOK_VERSION=0.6.0

LABEL org.opencontainers.image.title="blockbook-neurai" \
      org.opencontainers.image.description="Blockbook indexer and explorer for Neurai" \
      org.opencontainers.image.version="${BLOCKBOOK_VERSION}" \
      org.opencontainers.image.source="https://github.com/NeuraiProject/blockbook" \
      org.opencontainers.image.vendor="Neurai Project"

# apt resolves the shared-library dependencies declared by the .deb
# (libzmq5, libsnappy1v5, libzstd1, liblz4-1, libbz2-1.0, ...).
# curl is used by the healthcheck.
COPY --from=fetch /blockbook-neurai.deb /tmp/blockbook-neurai.deb
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl /tmp/blockbook-neurai.deb \
 && rm -f /tmp/blockbook-neurai.deb \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && dpkg-query -W -f='blockbook-neurai ${Version}\n' blockbook-neurai \
 && ! ldd /opt/coins/blockbook/neurai/bin/blockbook | grep 'not found'

COPY blockbook-neurai/entrypoint.sh blockbook-neurai/healthcheck.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

ENV BLOCKBOOK_INSTALL_DIR=/opt/coins/blockbook/neurai \
    BLOCKBOOK_DATA_DIR=/opt/coins/data/neurai/blockbook \
    BLOCKBOOK_RUN_DIR=/run/blockbook \
    BLOCKBOOK_USER=blockbook-neurai \
    BLOCKBOOK_INTERNAL_PORT=9069 \
    BLOCKBOOK_PUBLIC_PORT=9169 \
    BACKEND_HOST=backend-neurai \
    BLOCKBOOK_CERTFILE= \
    BLOCKBOOK_EXPLORER_URL= \
    BLOCKBOOK_DBCACHE=536870912 \
    BLOCKBOOK_WORKERS=8

VOLUME ["/opt/coins/data/neurai/blockbook"]

# 9169 = public API/explorer, 9069 = internal status/metrics
EXPOSE 9169 9069

HEALTHCHECK --interval=30s --timeout=10s --start-period=2m --retries=5 \
  CMD ["/usr/local/bin/healthcheck.sh"]

WORKDIR /opt/coins/blockbook/neurai
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
