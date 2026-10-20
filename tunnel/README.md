# Cloudflare Tunnel in this sandbox

Runs a Cloudflare Tunnel from inside the Cline Cloud sandbox so a local
service is reachable from the public internet.

## Layout

| path | purpose |
|---|---|
| `/workspace/bin/cloudflared` | the binary (v2026.10.1) |
| `/workspace/tunnel/run.sh` | watchdog: restarts `cloudflared` if it dies |
| `/workspace/tunnel/serve.sh` | watchdog: serves `/workspace/public` on `127.0.0.1:3000` |
| `/workspace/tunnel/start.sh` | start / stop / status helper |
| `/workspace/tunnel/config.yml` | **named tunnel** config (stable hostname) — fill in the placeholders |
| `/workspace/tunnel/quick.yml` | quick tunnel (random `trycloudflare.com` URL) |
| `/workspace/tunnel/tunnel.log` | tunnel log |

## Usage

```bash
# one-time: named tunnel (needs a Cloudflare account)
cloudflared tunnel create my-sandbox
cloudflared tunnel route dns my-sandbox dev.example.com
cloudflared tunnel token create my-sandbox    # paste into config.yml
cloudflared tunnel token create my-sandbox > /workspace/tunnel/<UUID>.json
# edit config.yml: tunnel / credentials-file / token / hostname

/workspace/tunnel/start.sh            # start named tunnel
/workspace/tunnel/start.sh quick      # start quick tunnel (no account)
/workspace/tunnel/start.sh status     # pid + current public URL
/workspace/tunnel/start.sh stop       # stop everything
```

## Verified behaviour in this sandbox

- egress to Cloudflare works: TCP 443/7844/8080 to `region1/region2.v2.argotunnel.com` open
- TLS validates against the **system** trust store (not MITM-broken) for
  `api.cloudflare.com`, `region1.v2.argotunnel.com`, `update.argotunnel.com`
- `cloudflared` precheck reports `HTTP/2 connection successful` and registers
  a tunnel connection; public URL returns HTTP 200
- `kill -9` on the tunnel → watchdog restarts it ~5 s later and the public URL
  serves traffic again (quick tunnel gets a **new random URL** each restart;
  a named tunnel keeps the same hostname)

## Why `--protocol http2`

`cloudflared` prefers QUIC over UDP/7844. UDP egress is not guaranteed from
this sandbox, and cloudflared's own precheck recommends `http2` here, so the
config forces HTTP/2 over TCP 443.

## Caveats — read before relying on it

1. **The pod is ephemeral.** The sandbox is created per task by the Cline Cloud
   control plane and may be reclaimed. Nothing inside the container can prevent
   that. The watchdog survives a *crash*; it does not survive *pod eviction*.
2. **No systemd.** PID 1 is the `cline-core` hub, so `systemctl enable` is not
   available — the supervisors are plain `setsid nohup` loops. If the pod
   restarts, re-run `start.sh`.
3. **Only expose a dedicated directory.** `/workspace` contains git
   credentials, the hub auth token and `~/.cline` session data. Point the
   tunnel at `/workspace/public` only, and put Cloudflare Access in front of it.
4. Quick tunnel URLs are random and change on every restart. Use a named
   tunnel for anything you want to keep.
5. The binary is not committed to git (see `.gitignore`); re-download it with
   `curl -sSL -o /workspace/bin/cloudflared
   https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64`
   after a fresh sandbox.
