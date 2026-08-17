#!/usr/bin/env bash
# Probe the internal (status/metrics) server. It speaks TLS when a certfile is set.
port=${BLOCKBOOK_INTERNAL_PORT:-9069}
scheme=http
[ -n "${BLOCKBOOK_CERTFILE:-}" ] && scheme=https
exec curl -fsSk -o /dev/null --max-time 8 "${scheme}://127.0.0.1:${port}/"
