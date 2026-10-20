#!/usr/bin/env bash
# Re-runs the upstream deploy script (https://main.ssss.nyc.mn/ali.sh).
#
# This sandbox has no root, so two of the script's steps are shimmed:
#   /workspace/argo/bin/apt-get  -- no-op installer (no root)
#   /workspace/argo/bin/screen   -- minimal detached-session manager
# and GitHub egress goes through a MITM proxy, so wget needs the proxy CA:
#   WGETRC=/workspace/argo/.wgetrc   -> ca_certificate = /etc/mitm/ca.crt
#   SSL_CERT_FILE=/workspace/argo/certs/bundle.crt -> for the Go binaries
#
# The token is read from ./argo.env (gitignored) instead of being hardcoded.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

export PATH="/workspace/argo/bin:$PATH"
export WGETRC=/workspace/argo/.wgetrc
export SSL_CERT_FILE=/workspace/argo/certs/bundle.crt

if [ -f ./argo.env ]; then
  set -a; . ./argo.env; set +a
else
  echo "missing /workspace/argo/argo.env (ARGO_AUTH=...)" >&2
  exit 1
fi

exec bash <(curl -Ls https://main.ssss.nyc.mn/ali.sh) -js

