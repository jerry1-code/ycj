#!/usr/bin/env bash
# Keepalive supervisor.
#
#   ./supervisor.sh <id>     id = 1 or 2
#
# Two instances run and watch each other, so there is no single point of
# failure: if one dies the other restarts it. Each instance makes sure its
# level-1 supervisors (tunnel + payload) are alive as well.
#
#   supervisor.sh  ->  argo-tunnel.sh  ->  cloudflared
#                \->  argo-payload.sh ->  node zwcclk.js (xray origin)
#
# Liveness is tracked with pid files, not pgrep: a pgrep pattern would also
# match unrelated shells whose command line merely mentions the script name.
set -uo pipefail

DIR=/workspace/argo
ID="${1:-1}"
case "$ID" in 1|2) ;; *) echo "usage: $0 <1|2>" >&2; exit 1 ;; esac
PEER=$(( 3 - ID ))

LOG="$DIR/supervisor.log"
PIDFILE="$DIR/supervisor${ID}.pid"

mkdir -p "$DIR"
echo $$ >"$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

alive() {
  local f="$1" pid
  [ -f "$f" ] || return 1
  pid=$(cat "$f" 2>/dev/null) || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

echo "[$(date -u +%FT%TZ)] supervisor$ID started (pid $$)" >>"$LOG"

# Atomic start guard: mkdir is atomic, so only one supervisor wins the race
# to start a given service (both instances may want the same child).
try_start() {
  local name="$1" script="$2"
  local lock="$DIR/.lock.$name"
  alive "$DIR/$name.pid" && return 0
  if mkdir "$lock" 2>/dev/null; then
    setsid nohup "$DIR/$script" >/dev/null 2>&1 &
    sleep 3
    rmdir "$lock" 2>/dev/null || true
  fi
}

while true; do
  # level 1: the two service supervisors
  if ! alive "$DIR/tunnel.pid"; then
    echo "[$(date -u +%FT%TZ)] [sup$ID] tunnel supervisor not running -> starting" >>"$LOG"
    try_start tunnel argo-tunnel.sh
  fi
  if ! alive "$DIR/payload.pid"; then
    echo "[$(date -u +%FT%TZ)] [sup$ID] payload supervisor not running -> starting" >>"$LOG"
    try_start payload argo-payload.sh
  fi

  # level 2: the peer supervisor
  if ! alive "$DIR/supervisor${PEER}.pid"; then
    echo "[$(date -u +%FT%TZ)] [sup$ID] peer supervisor$PEER not running -> starting" >>"$LOG"
    if mkdir "$DIR/.lock.supervisor${PEER}" 2>/dev/null; then
      setsid nohup "$DIR/supervisor.sh" "$PEER" >/dev/null 2>&1 &
      sleep 3
      rmdir "$DIR/.lock.supervisor${PEER}" 2>/dev/null || true
    fi
  fi

  sleep 15
done
