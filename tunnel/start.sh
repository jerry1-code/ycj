#!/usr/bin/env bash
# Start / stop / status helper for the sandbox tunnel watchdog.
#
#   ./start.sh            -> start watchdog with named-tunnel config.yml
#   ./start.sh quick      -> start watchdog with quick.yml (random URL)
#   ./start.sh stop       -> stop watchdog + cloudflared
#   ./start.sh status     -> show pid, url, last log lines
set -uo pipefail

DIR=/workspace/tunnel
LOG="$DIR/tunnel.log"
PIDFILE="$DIR/tunnel.pid"

case "${1:-start}" in
  stop)
    [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null
    pkill -x -f '/workspace/tunnel/run.sh' 2>/dev/null
    pkill -x cloudflared 2>/dev/null
    rm -f "$PIDFILE"
    echo "stopped"
    ;;
  status)
    echo "pid:      $(cat "$PIDFILE" 2>/dev/null || echo none)"
    echo "url:      $(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" 2>/dev/null | tail -1 || echo none)"
    echo "conns:    $(grep -c 'Registered tunnel connection' "$LOG" 2>/dev/null || echo 0)"
    tail -5 "$LOG" 2>/dev/null
    ;;
  quick)
    setsid nohup "$DIR/run.sh" "$DIR/quick.yml" >/dev/null 2>&1 &
    echo "started (quick tunnel, random url)"
    ;;
  *)
    if [ ! -f "$DIR/config.yml" ] || grep -q REPLACE "$DIR/config.yml"; then
      echo "config.yml still has placeholders -- edit it first, or use: $0 quick"
      exit 1
    fi
    setsid nohup "$DIR/run.sh" "$DIR/config.yml" >/dev/null 2>&1 &
    echo "started (named tunnel)"
    ;;
esac
