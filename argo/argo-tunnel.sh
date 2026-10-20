#!/usr/bin/env bash
# Supervises the official cloudflared connector for the Argo tunnel.
# The payload's embedded bot.so connector does not establish a tunnel in this
# sandbox, so we run the official binary with the same token instead.
# CF-side ingress maps cline.96789.ggff.net -> http://localhost:8001
set -uo pipefail

DIR=/workspace/argo
BIN=/workspace/bin/cloudflared
LOG="$DIR/argo-tunnel.log"

export SSL_CERT_FILE="$DIR/certs/bundle.crt"

TOKEN=""
if [ -f "$DIR/argo.env" ]; then
  TOKEN=$(sed -n 's/^ARGO_AUTH=//p' "$DIR/argo.env" | tr -d '"'"'"' \r\n')
fi
if [ -z "$TOKEN" ]; then
  echo "ARGO_AUTH missing -- put it in $DIR/argo.env as ARGO_AUTH=<token>" >&2
  exit 1
fi

mkdir -p "$DIR"
while true; do
  echo "[$(date -u +%FT%TZ)] starting cloudflared" >>"$LOG"
  "$BIN" tunnel --edge-ip-version auto --no-autoupdate --protocol http2 \
    run --token "$TOKEN" >>"$LOG" 2>&1
  echo "[$(date -u +%FT%TZ)] cloudflared exited, restarting in 5s" >>"$LOG"
  sleep 5
done

