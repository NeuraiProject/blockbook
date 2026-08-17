#!/usr/bin/env bash
# Entrypoint for the blockbook-neurai container.
#
# The .deb ships blockchaincfg.json pointing at 127.0.0.1 (RPC + ZMQ). In the
# compose stack the node lives in the `backend-neurai` service, so a runtime
# copy of the config is generated with the backend host substituted. Blockbook
# then runs in the foreground, as the unprivileged `blockbook-neurai` user,
# logging to stderr (docker logs).
#
# If the first argument is not a flag, it is executed instead of blockbook
# (e.g. `docker compose run --rm blockbook-neurai bash`).
set -euo pipefail

INSTALL_DIR=${BLOCKBOOK_INSTALL_DIR:-/opt/coins/blockbook/neurai}
DATA_DIR=${BLOCKBOOK_DATA_DIR:-/opt/coins/data/neurai/blockbook}
RUN_DIR=${BLOCKBOOK_RUN_DIR:-/run/blockbook}
SVC_USER=${BLOCKBOOK_USER:-blockbook-neurai}
PKG_CFG=${INSTALL_DIR}/config/blockchaincfg.json
RUNTIME_CFG=${RUN_DIR}/blockchaincfg.json

BACKEND_HOST=${BACKEND_HOST:-backend-neurai}
BACKEND_RPC_URL=${BACKEND_RPC_URL:-}
BACKEND_MQ_URL=${BACKEND_MQ_URL:-}
RPC_USER=${RPC_USER:-}
RPC_PASS=${RPC_PASS:-}
INTERNAL_PORT=${BLOCKBOOK_INTERNAL_PORT:-9069}
PUBLIC_PORT=${BLOCKBOOK_PUBLIC_PORT:-9169}
CERTFILE=${BLOCKBOOK_CERTFILE:-}
EXPLORER_URL=${BLOCKBOOK_EXPLORER_URL:-}
DBCACHE=${BLOCKBOOK_DBCACHE:-}
WORKERS=${BLOCKBOOK_WORKERS:-}
BLOCKBOOK_EXTRA_ARGS=${BLOCKBOOK_EXTRA_ARGS:-}

log() { echo "[entrypoint] $*" >&2; }

# Run an arbitrary command if requested (anything that does not start with '-').
if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
    exec "$@"
fi

if [ ! -f "$PKG_CFG" ]; then
    log "packaged config not found: $PKG_CFG"; exit 1
fi

mkdir -p "$RUN_DIR" "$DATA_DIR/db"

# ---------------------------------------------------------------------------
# Generate runtime blockchaincfg.json
# ---------------------------------------------------------------------------
# 1) point every 127.0.0.1 endpoint (rpc_url, rpc_url_ws, message_queue_binding)
#    at the backend service;
# 2) optional full overrides of rpc_url / message_queue_binding;
# 3) optional RPC credentials (must match the backend container).
sed -E "s#(://)127\.0\.0\.1(:[0-9]+)#\1${BACKEND_HOST}\2#g" "$PKG_CFG" > "$RUNTIME_CFG"
if [ -n "$BACKEND_RPC_URL" ]; then
    sed -i -E "s#(\"rpc_url\"[[:space:]]*:[[:space:]]*\")[^\"]*\"#\1${BACKEND_RPC_URL}\"#" "$RUNTIME_CFG"
fi
if [ -n "$BACKEND_MQ_URL" ]; then
    sed -i -E "s#(\"message_queue_binding\"[[:space:]]*:[[:space:]]*\")[^\"]*\"#\1${BACKEND_MQ_URL}\"#" "$RUNTIME_CFG"
fi
if [ -n "$RPC_USER" ]; then
    sed -i -E "s#(\"rpc_user\"[[:space:]]*:[[:space:]]*\")[^\"]*\"#\1${RPC_USER}\"#" "$RUNTIME_CFG"
fi
if [ -n "$RPC_PASS" ]; then
    sed -i -E "s#(\"rpc_pass\"[[:space:]]*:[[:space:]]*\")[^\"]*\"#\1${RPC_PASS}\"#" "$RUNTIME_CFG"
fi

# ---------------------------------------------------------------------------
# Privileges: fix ownership (only when needed) and drop to the service user.
# ---------------------------------------------------------------------------
if [ "$(id -u)" = "0" ]; then
    uid=$(id -u "$SVC_USER"); gid=$(id -g "$SVC_USER")
    chown "$uid:$gid" "$RUN_DIR" "$RUNTIME_CFG"
    chmod 0640 "$RUNTIME_CFG"
    # $DATA_DIR/db is created above (possibly as root) — check both levels.
    for d in "$DATA_DIR" "$DATA_DIR/db"; do
        if [ "$(stat -c '%u' "$d")" != "$uid" ]; then
            log "fixing ownership of $d (this can take a while on large data dirs)"
            chown -R "$uid:$gid" "$d"
        fi
    done
    if [ -d "$INSTALL_DIR/logs" ] && [ "$(stat -c '%u' "$INSTALL_DIR/logs")" != "$uid" ]; then
        chown -R "$uid:$gid" "$INSTALL_DIR/logs"
    fi
    run_as=(setpriv --reuid="$uid" --regid="$gid" --init-groups)
else
    run_as=()
fi

args=(
    -blockchaincfg="$RUNTIME_CFG"
    -datadir="${DATA_DIR}/db"
    -sync
    -internal=":${INTERNAL_PORT}"
    -public=":${PUBLIC_PORT}"
    -explorer="${EXPLORER_URL}"
    -log_dir="${INSTALL_DIR}/logs"
    -logtostderr
)
if [ -n "$CERTFILE" ]; then args+=(-certfile="$CERTFILE"); fi
if [ -n "$DBCACHE" ];  then args+=(-dbcache="$DBCACHE"); fi
if [ -n "$WORKERS" ];  then args+=(-workers="$WORKERS"); fi

rpc_url=$(sed -nE 's#.*"rpc_url"[[:space:]]*:[[:space:]]*"([^"]*)".*#\1#p' "$RUNTIME_CFG")
mq_url=$(sed -nE 's#.*"message_queue_binding"[[:space:]]*:[[:space:]]*"([^"]*)".*#\1#p' "$RUNTIME_CFG")
log "starting blockbook (backend rpc=$rpc_url mq=$mq_url public=:${PUBLIC_PORT}$([ -n "$CERTFILE" ] && echo ' TLS' || echo ' HTTP') internal=:${INTERNAL_PORT})"

# blockbook resolves ./static relative to the working directory
cd "$INSTALL_DIR"
# shellcheck disable=SC2086
exec "${run_as[@]}" "${INSTALL_DIR}/bin/blockbook" "${args[@]}" $BLOCKBOOK_EXTRA_ARGS "$@"
