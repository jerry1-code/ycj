#!/usr/bin/env bash
# Supervises the local origin service that the tunnel points at.
# Serves /workspace/public on 127.0.0.1:3000.
set -uo pipefail

ROOT=/workspace/public
PORT=3000
LOG=/workspace/tunnel/serve.log
mkdir -p "$ROOT" /workspace/tunnel

while true; do
  echo "[$(date -u +%FT%TZ)] starting static server on 127.0.0.1:$PORT" >>"$LOG"
  cd "$ROOT" && python3 -m http.server "$PORT" --bind 127.0.0.1 >>"$LOG" 2>&1
  echo "[$(date -u +%FT%TZ)] server exited, restarting in 3s" >>"$LOG"
  sleep 3
done
