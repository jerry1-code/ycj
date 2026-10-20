#!/usr/bin/env bash
# Idempotent starter for the whole Argo stack.
# Safe to run any number of times, and safe to run right after the sandbox
# pod has been recreated (nothing else starts these automatically -- there is
# no systemd here).
#
#   ./start-all.sh          -> ensure everything is running
#   ./start-all.sh status   -> show what is running
#   ./start-all.sh stop     -> stop the supervisor chain
set -uo pipefail

DIR=/workspace/argo
cd "$DIR" || exit 1

alive() {
  local f="$1" pid
  [ -f "$f" ] || return 1
  pid=$(cat "$f" 2>/dev/null) || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

case "${1:-start}" in
  status)
    alive "$DIR/supervisor1.pid" && echo "OK      supervisor1 (pid $(cat "$DIR/supervisor1.pid"))" \
                                 || echo "MISSING supervisor1"
    alive "$DIR/supervisor2.pid" && echo "OK      supervisor2 (pid $(cat "$DIR/supervisor2.pid"))" \
                                 || echo "MISSING supervisor2"
    alive "$DIR/tunnel.pid"   && echo "OK      tunnel supervisor (pid $(cat "$DIR/tunnel.pid"))" \
                              || echo "MISSING tunnel supervisor"
    alive "$DIR/payload.pid"  && echo "OK      payload supervisor (pid $(cat "$DIR/payload.pid"))" \
                              || echo "MISSING payload supervisor"
    pgrep -x cloudflared >/dev/null 2>&1 && echo "OK      cloudflared connector" || echo "MISSING cloudflared connector"
    pgrep -f 'node zwcclk[.]js' >/dev/null 2>&1 && echo "OK      payload (xray origin)" || echo "MISSING payload (xray origin)"
    echo "--- tunnel connections registered (last 200 log lines) ---"
    tail -200 "$DIR/argo-tunnel.log" 2>/dev/null | grep -c 'Registered tunnel connection'
    ;;
  stop)
    # kill by pid file first (reliable), then sweep any strays by pattern
    for f in "$DIR"/*.pid; do
      [ -e "$f" ] || continue
      p=$(cat "$f" 2>/dev/null)
      [ -n "${p:-}" ] && kill "$p" 2>/dev/null
      rm -f "$f"
    done
    pkill -f 'argo/supervisor[.]sh' 2>/dev/null
    pkill -f 'argo/argo-tunnel[.]sh' 2>/dev/null
    pkill -f 'argo/argo-payload[.]sh' 2>/dev/null
    pkill -f 'argo-payload[.]sh' 2>/dev/null
    pkill -f 'argo-tunnel[.]sh' 2>/dev/null
    pkill -f 'cloudflared tunnel' 2>/dev/null
    pkill -f 'node zwcclk[.]js' 2>/dev/null
    sleep 1
    echo "stopped"
    ;;
  *)
    if [ ! -x /workspace/bin/cloudflared ]; then
      echo "downloading cloudflared..."
      mkdir -p /workspace/bin
      curl -sSL -o /workspace/bin/cloudflared \
        https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
        && chmod +x /workspace/bin/cloudflared
    fi
    for id in 1 2; do
      if alive "$DIR/supervisor${id}.pid"; then
        echo "supervisor$id already running (pid $(cat "$DIR/supervisor${id}.pid"))"
      else
        setsid nohup "$DIR/supervisor.sh" "$id" >/dev/null 2>&1 &
        echo "started supervisor$id"
      fi
    done
    sleep 6
    "$DIR/start-all.sh" status
    ;;
esac
