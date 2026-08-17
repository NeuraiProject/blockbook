#!/usr/bin/env bash
# Healthy once neuraid answers RPC (returns non-zero while "Loading block index").
exec /usr/local/bin/neurai-cli getblockchaininfo >/dev/null
