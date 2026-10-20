#!/usr/bin/env bash
# Watchdog: keeps a cloudflared tunnel alive inside this sandbox.
# Usage: ./run.sh [config.yml]   (default: /workspace/tunnel/config.yml)
set -uo pipefail

BIN=/workspace/bin/cloudflared
CONFIG="${1:-/workspace/tunnel/config.yml}"
LOG=/workspace/tunnel/tunnel.log
PIDFILE=/workspace/tunnel/tunnel.pid

mkdir -p /workspace/tunnel
: >"$LOG"

running() {
  [ -f "$PIDFILE" ] || return 1
  local pid
  pid=$(cat "$PIDFILE" 2>/dev/null) || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

while true; do
  if running; then
    sleep 10
    continue
  fi
  echo "[$(date -u +%FT%TZ)] starting cloudflared" >>"$LOG"
  # --no-autoupdate: never let a failed self-update kill the tunnel
  # --protocol http2: UDP/7844 (QUIC) egress is not guaranteed here
  setsid "$BIN" tunnel --no-autoupdate --protocol http2 --config "$CONFIG" \
    >>"$LOG" 2>&1 &
  echo $! >"$PIDFILE"
  wait $! 2>/dev/null
  echo "[$(date -u +%FT%TZ)] cloudflared exited, restarting in 5s" >>"$LOG"
  rm -f "$PIDFILE"
  sleep 5
done
