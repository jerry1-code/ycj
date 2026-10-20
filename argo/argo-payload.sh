#!/usr/bin/env bash
# Supervises the node payload (xray VLESS + subscription server).
# The payload is started with the same argv the deploy script uses; if it dies,
# it is restarted so the Argo origin (localhost:8001) stays alive.
set -uo pipefail

DIR=/workspace/argo
LOG="$DIR/payload.log"
PIDFILE="$DIR/payload.pid"
export SSL_CERT_FILE="$DIR/certs/bundle.crt"
export WGETRC="$DIR/.wgetrc"

mkdir -p "$DIR"

# the payload reads its config from .env in its own directory
cd "$DIR" || exit 1
set -a; [ -f "$DIR/.env" ] && . "$DIR/.env"; set +a

echo $$ >"$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

while true; do
  echo "[$(date -u +%FT%TZ)] starting payload" >>"$LOG"
  # If a previous supervisor was SIGKILLed its node child can survive as an
  # orphan and keep holding ports 3000/8001, which would make this instance
  # crash-loop with EADDRINUSE. Clear any stale instance before starting.
  # SIGKILL, not SIGTERM: the payload installs its own SIGTERM handler and
  # does not exit on it.
  pkill -9 -f 'node zwcclk[.]js' 2>/dev/null
  sleep 2
  node zwcclk.js >>"$LOG" 2>&1
  echo "[$(date -u +%FT%TZ)] payload exited, restarting in 5s" >>"$LOG"
  sleep 5
done
