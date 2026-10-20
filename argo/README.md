# Argo tunnel deployment (`eooce` node-ws / xray-over-Argo)

Deploys a VLESS-over-WebSocket node served through a Cloudflare Argo tunnel at
`cline.96789.ggff.net`, running the upstream script
`https://main.ssss.nyc.mn/ali.sh` (nodejs variant) inside this sandbox.

## Keepalive

Three layers, each restarting the one below it. There is no systemd in this
sandbox (PID 1 is the `cline-core` hub, which supervises nothing), so the
keepalive is built from plain processes.

```
supervisor.sh 1  <──peer──>  supervisor.sh 2      (mutual watch, no SPOF)
      │                                  │
      ├─ argo-tunnel.sh  ──> cloudflared connector
      └─ argo-payload.sh ──> node zwcclk.js  (xray origin + subscription)
```

- `supervisor.sh <1|2>` — two instances that watch each other *and* the two
  service supervisors. If one dies, the peer restarts it.
- `argo-tunnel.sh` / `argo-payload.sh` — restart their own child when it exits.
- Liveness is tracked with **pid files** (`supervisor1.pid`, `supervisor2.pid`,
  `tunnel.pid`, `payload.pid`), not `pgrep -f`: a `pgrep` pattern also matches
  unrelated shells whose command line merely mentions the script name, which
  produced false "alive" readings.
- The check is stricter than `kill -0`: PID 1 here is the node hub, which does
  not reap orphans, so a killed process lingers as a **zombie** and `kill -0`
  still succeeds for it. The check therefore also requires the pid to be
  non-zombie and its `/proc/<pid>/cmdline` to match the expected program
  (which also rules out a recycled pid). Without this, the keepalive believed
  dead supervisors were alive and never replaced them.
- Concurrent starts are prevented with an atomic `mkdir` lock
  (`argo/.lock.<name>`), so the two supervisors never spawn duplicate children.

### Commands

```bash
/workspace/argo/start-all.sh            # idempotent: start everything
/workspace/argo/start-all.sh status     # what is running
/workspace/argo/start-all.sh stop       # stop the whole chain
```

### Verified

Every scenario below was exercised with `kill -9`; after each one the node
still answered `101 Switching Protocols` on all three paths:

| killed | recovered by | result |
|---|---|---|
| `cloudflared` connector | `argo-tunnel.sh` | 3/3 paths OK |
| `node zwcclk.js` (xray origin) | `argo-payload.sh` | 3/3 paths OK |
| `supervisor.sh 1` | peer `supervisor.sh 2` | 3/3 paths OK |
| `supervisor.sh 2` | peer `supervisor.sh 1` | 3/3 paths OK |
| both service supervisors | the two `supervisor.sh` | 3/3 paths OK |

### What keepalive cannot cover

- **Pod eviction.** If the Cline Cloud control plane reclaims the sandbox,
  every process dies with it and nothing inside the container can prevent
  that. Recovery is one command: `/workspace/argo/start-all.sh` (all scripts
  and the downloaded payloads live on the persistent workspace volume).
- **PID 1 exiting.** The hub is the container's init; if it dies the container
  is torn down.

## Layout

| path | purpose |
|---|---|
| `argo/bin/apt-get` | rootless no-op installer (script calls `apt-get update/install`) |
| `argo/bin/screen` | minimal detached-session manager (real `screen` needs root + newer glibc) |
| `argo/run-deploy.sh` | re-runs the upstream deploy script with the fixes below applied |
| `argo/argo-payload.sh` | watchdog for the node payload (xray + subscription server) |
| `argo/argo-tunnel.sh` | watchdog for the cloudflared connector |
| `argo/argo.env` | `ARGO_AUTH=<tunnel token>` — **gitignored, secret** |
| `argo/.env` | payload env (UUID, ARGO_DOMAIN, ARGO_PORT) — **gitignored** |
| `argo/.npm/` | payload runtime dir: `web.so` (xray), `bot.so`, `config.json`, `sub.txt` |
| `argo/certs/bundle.crt` | system CAs **+** the sandbox MITM CA, for the Go binaries |

## Ports

| port | who | purpose |
|---|---|---|
| 8001 | xray (in payload) | VLESS inbound; **this is the Argo origin** |
| 3000 | payload | subscription page (`/sub`) + landing page |
| 55001-55004 | xray | VLESS/VMess/Trojan fallbacks |

Cloudflare's side already maps `cline.96789.ggff.net -> http://localhost:8001`,
so the tunnel origin must stay on **8000/8001** as configured (`ARGO_PORT`).

## Running

```bash
setsid nohup /workspace/argo/argo-payload.sh >/dev/null 2>&1 &   # xray origin
setsid nohup /workspace/argo/argo-tunnel.sh  >/dev/null 2>&1 &   # cloudflared connector
```

Both supervisors restart their child on exit (verified: `kill -9` on either one
→ it comes back and the node serves again).

## Three sandbox-specific fixes that were required

1. **No root / no sudo** — the upstream script calls `apt-get update` and
   `apt-get install screen`, and runs under `set -e`, so it aborted
   immediately. Fixed with the `argo/bin/apt-get` and `argo/bin/screen` shims
   (prepended to `PATH`).
2. **MITM proxy on GitHub egress** — `wget` failed with *"certificate is not
   trusted"* because the sandbox proxy signs GitHub traffic with its own CA
   (`cline-mitm-ca`). Fixed with `WGETRC` (`ca_certificate = /etc/mitm/ca.crt`)
   for wget and `SSL_CERT_FILE` (system CAs + proxy CA) for the Go binaries.
3. **The payload's embedded connector does not tunnel** — `bot.so` is a Go
   shared library loaded into node via koffi; its internal cloudflared never
   registers a tunnel connection here (the domain just returns CF edge
   **502**). The same token works perfectly with the **official** cloudflared
   binary, so `argo/argo-tunnel.sh` runs that instead. The origin side (xray
   inside the payload) is unaffected.

## Verification

```bash
# WebSocket handshake through the public domain
python3 - <<'EOF'
import socket, ssl, base64, os
host="cline.96789.ggff.net"; path="/vless-argo"
key=base64.b64encode(os.urandom(16)).decode()
req=(f"GET {path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
     f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
ctx=ssl.create_default_context()
with socket.create_connection((host,443),timeout=20) as raw:
    with ctx.wrap_socket(raw,server_hostname=host) as s:
        s.sendall(req.encode()); print(s.recv(4096).split(b"\r\n")[0].decode())
EOF
# -> HTTP/1.1 101 Switching Protocols
```

All three node paths return **101 Switching Protocols**:
`/vless-argo`, `/vmess-argo`, `/trojan-argo`.
`/` returns 502 by design — its fallback is the plain-TCP VLESS inbound.

## Caveats

- The pod is ephemeral: the sandbox may be reclaimed by the Cline Cloud
  control plane. There is no systemd here, so after a pod restart re-run the
  two `setsid nohup` commands above (the scripts and the downloaded payloads
  live on the persistent workspace volume).
- `argo/argo.env` and `argo/.env` hold the tunnel token and are gitignored.
  `argo/.npm/private.key` and `cert.pem` are the node's TLS material.
- The payload needs `node`, `npm` and outbound access to GitHub/npm; it
  re-downloads `web.so`/`bot.so` (~70 MB) on a fresh deploy.
