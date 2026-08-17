# Neurai Blockbook — Docker Compose

Production-oriented `docker compose` stack for a Neurai Blockbook explorer.
It replaces the single-container image from
[NeuraiProject/docker/blockbook](https://github.com/NeuraiProject/docker/tree/main/blockbook)
with two purpose-built services that install the very same `.deb` packages this
repository produces (`make deb-neurai`).

```
                 ┌──────────────────────────┐   RPC 8069 / ZMQ 38369   ┌──────────────────────────┐
  (no ports)     │  backend-neurai (neuraid) │◀────── compose network ──│  blockbook-neurai         │◀── 127.0.0.1:9169 API/explorer (nginx in front)
                 │  vol: backend-data        │                          │  vol: blockbook-data      │◀── 127.0.0.1:9069 metrics
                 └──────────────────────────┘                          └──────────────────────────┘
```

| Service            | Image (built locally)                    | Runs as            | Data volume                          |
|--------------------|------------------------------------------|--------------------|--------------------------------------|
| `backend-neurai`   | `neuraiproject/backend-neurai:<ver>`     | `neurai` (uid 999) | `/opt/coins/data/neurai/backend`     |
| `blockbook-neurai` | `neuraiproject/blockbook-neurai:<ver>`   | `blockbook-neurai` | `/opt/coins/data/neurai/blockbook`   |

## Quick start

```bash
cd docker
docker compose up -d --build        # builds both images, starts the node, then blockbook
docker compose logs -f              # follow both
```

* Explorer / REST / WebSocket API: <http://127.0.0.1:9169/> (`/api/` for status JSON)
* Internal status + Prometheus metrics: <http://127.0.0.1:9069/metrics>

Both ports are bound to **loopback only** by default — the expected setup is a
reverse proxy (nginx, Caddy, Traefik) on the same host terminating TLS (see
below). Set `BLOCKBOOK_PUBLIC_BIND=0.0.0.0` in `.env` if you really want
`:9169` reachable from outside without a proxy.

Blockbook is started only after the node answers RPC (`depends_on: service_healthy`).
Both services restart automatically (`unless-stopped`).

The node publishes **no host port** (outbound-only, RPC/ZMQ stay on the compose
network), so the stack can run next to an existing `neuraid` on the same
server. To accept inbound P2P connections add the overlay
[`docker-compose.p2p.yml`](docker-compose.p2p.yml) (see Configuration).

## Where do the packages come from?

Each image installs one `.deb`:

| Package                                          | Built by                       |
|--------------------------------------------------|--------------------------------|
| `backend-neurai_<BACKEND_VERSION>-neurai-dev_amd64.deb` | `make deb-backend-neurai` (repo root) |
| `blockbook-neurai_<BLOCKBOOK_VERSION>_amd64.deb`  | `make deb-blockbook-neurai` (repo root) |

Resolution order at `docker compose build` time:

1. **Local drop-in** — any matching `.deb` in [`debs/`](debs/) (git-ignored):
   ```bash
   make deb-neurai                      # from the repo root
   cp build/*.deb docker/debs/
   cd docker && docker compose build
   ```
2. **GitHub release** — otherwise the files are downloaded from
   `https://github.com/NeuraiProject/blockbook/releases/download/${BLOCKBOOK_RELEASE}/…`
   (defaults: `v0.6.0`, blockbook `0.6.0`, backend `1.0.6.0`).
3. `BACKEND_DEB_URL` / `BLOCKBOOK_DEB_URL` — explicit URLs override everything.

To use another release without touching any file:

```bash
BLOCKBOOK_RELEASE=v0.5.0 BLOCKBOOK_VERSION=0.5.0 BACKEND_VERSION=1.0.5.0 docker compose up -d --build
```

## Configuration

Copy [`.env.example`](.env.example) to `.env` and edit. Everything has a
default, so `.env` is optional. Most relevant knobs:

| Variable | Default | Purpose |
|---|---|---|
| `BLOCKBOOK_PUBLIC_BIND` | `127.0.0.1` | Host address the explorer/API is bound to (`0.0.0.0` = exposed directly, no proxy) |
| `BLOCKBOOK_PUBLIC_PORT` | `9169` | Host port for the explorer/API |
| `BLOCKBOOK_INTERNAL_PORT` | `9069` | Host loopback port for status/metrics |
| `BLOCKBOOK_CERTFILE` | *(empty → HTTP)* | Set to `/opt/coins/blockbook/neurai/cert/blockbook` for the self-signed TLS cert shipped in the .deb, or mount your own `<path>.crt/.key` |
| `BLOCKBOOK_EXPLORER_URL` | *(empty)* | Public URL used in links |
| `BLOCKBOOK_DBCACHE` / `BLOCKBOOK_WORKERS` | `536870912` / `8` | RocksDB cache (bytes) / initial-sync workers |
| `BLOCKBOOK_EXTRA_ARGS` | *(empty)* | Extra `blockbook` flags |
| `COMPOSE_FILE` | `docker-compose.yml` | Set to `docker-compose.yml:docker-compose.p2p.yml` to accept inbound P2P on `BACKEND_P2P_PORT` (19000). Off by default: no host port is taken, safe next to another neuraid |
| `BACKEND_RPC_ALLOW_IP` | RFC-1918 ranges | Subnets allowed to call the node RPC (RPC/ZMQ are never published to the host) |
| `NEURAI_RPC_USER` / `NEURAI_RPC_PASS` | from the .deb (`rpc`/`rpc`) | Shared by both containers |
| `NEURAID_EXTRA_ARGS` | *(empty)* | Extra `neuraid` flags (`-dbcache=2000 …`) |
| `BACKEND_DATA` / `BLOCKBOOK_DATA` | named volumes | Absolute (or `./`) path → bind mount instead |

### How the containers adapt the packaged configs

The `.deb` files are generated for a single host (everything on `127.0.0.1`).
The entrypoints derive a runtime copy of each config on every start, without
modifying the packaged files:

* **backend** — `neurai.conf` minus `daemon/rpcbind/rpcallowip/zmqpub*/listen`, plus
  `daemon=0`, `printtoconsole=1`, `rpcbind=0.0.0.0`, the allowed subnets, ZMQ on
  `0.0.0.0:<packaged port>` and `listen=0|1`. Result: `/run/neurai/neurai.conf`.
* **blockbook** — `blockchaincfg.json` with `127.0.0.1` replaced by the
  `backend-neurai` service name in `rpc_url`, `rpc_url_ws` and
  `message_queue_binding`. Result: `/run/blockbook/blockchaincfg.json`.

Both then drop privileges (`setpriv`) to the package's system user and `exec`
the daemon as PID 1 (via `init: true`), so `SIGTERM` reaches it directly.

## Day-2 operations

```bash
docker compose ps                                   # health of both services
docker compose exec backend-neurai neurai-cli getblockchaininfo
docker compose exec backend-neurai neurai-cli getnetworkinfo
docker compose logs -f --tail=200 blockbook-neurai
curl -s http://localhost:9169/api/ | jq .           # sync state (blockbook + backend)

docker compose stop                                 # graceful (blockbook first, then the node)
docker compose down                                 # stop + remove containers, KEEP volumes
docker compose down -v                              # …and delete the chain + index (full resync!)
```

Graceful shutdown matters: `stop_grace_period` is 15 min for the node and 5 min
for blockbook — never `docker kill` them, RocksDB and the chainstate need to flush.

### Upgrading

```bash
# new release published on GitHub → bump versions in .env (or pass them inline)
docker compose build --pull
docker compose up -d
```

Volumes are kept, so blockbook only re-indexes from where it stopped. If the
Blockbook DB format changes between versions the log will say so at start
(`required data version …`); in that case remove the blockbook volume only:
`docker compose down && docker volume rm neurai-blockbook_blockbook-data`.

### Reverse proxy / TLS (nginx)

Blockbook listens on plain HTTP at `127.0.0.1:9169`. Terminate TLS in front and
forward both HTTP and the WebSocket endpoint (`/websocket`), which Trezor Suite
and most wallets use:

```nginx
server {
    listen 443 ssl http2;
    server_name xna-blockbook.example.org;

    ssl_certificate     /etc/letsencrypt/live/xna-blockbook.example.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/xna-blockbook.example.org/privkey.pem;

    location / {
        proxy_pass         http://127.0.0.1:9169;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        # WebSocket (/websocket) — required by Trezor Suite / wallets
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

Set `BLOCKBOOK_EXPLORER_URL=https://xna-blockbook.example.org` in `.env` so the
explorer generates absolute links with the public URL. If you prefer blockbook to
speak TLS itself instead, set `BLOCKBOOK_CERTFILE` and mount `<name>.crt` /
`<name>.key` into the container.

## What changed vs. `NeuraiProject/docker/blockbook`

| Old image | This stack |
|---|---|
| One `ubuntu:22.04` container running `neuraid` (daemonised) **and** blockbook from a shell script | Two `debian:12-slim` images, one process each — the 0.6.0 binaries are built on debian 12 (glibc 2.36) and **do not run on ubuntu 22.04** |
| Hard-coded old versions (backend 1.0.2, blockbook 0.4.0) | Versions are build args; local `.deb` drop-in or GitHub release |
| Both daemons as root, no healthchecks, no restart policy | Unprivileged users, healthchecks, `depends_on: service_healthy`, `restart: unless-stopped`, long stop grace period, `ulimits`, log rotation |
| RPC/ZMQ bound to `127.0.0.1` inside one container | RPC/ZMQ bound only on the compose network; blockbook published on loopback only (`127.0.0.1:9169` / `:9069`, reverse proxy in front) — inbound P2P is an opt-in overlay |
| Manual `docker run -v blockbook:/data …` | Named volumes (or bind mounts) per service, `.env`-driven config, `neurai-cli` helper |
| Logs to files inside the container | Logs to `docker logs`, json-file driver capped at 5 × 50 MB |
