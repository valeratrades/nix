#!/usr/bin/env bash
# Push the Cloudflare tunnel token onto the RUNNING rpi5.
#
# The cloudflared-tunnel unit reads TUNNEL_TOKEN from /var/lib/cloudflared.env —
# the ONLY place the token lives (never in the repo or store), same pattern as
# the wifi + server_upkeep secrets. The unit has ConditionPathExists on that file,
# so it stays inactive until this script has run.
#
# ONE-TIME, done by you (needs your Cloudflare account + a domain on it):
#   1. Cloudflare dashboard -> Zero Trust -> Networks -> Tunnels -> Create tunnel
#      -> "Cloudflared" -> name it (e.g. rpi5). Copy the token it shows.
#   2. Same screen -> Public Hostnames -> Add:
#        Subdomain/domain = your domain      Service = HTTP  ->  localhost:80
#      (Cloudflare creates the DNS record automatically — no A record / static IP.)
#   3. Stash the token in sops under key `cloudflare_tunnel_token`:
#        sops secrets/users/v/default.json
#   4. Run this script.
#
# Idempotent. Usage: ./provision-cloudflared.sh [SSH_HOST]   (default: admin@rpi5.local)
set -euo pipefail

HOST="${1:-admin@rpi5.local}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS="$HERE/../../secrets/users/v/default.json"

# Prefer an already-exported CLOUDFLARE_TUNNEL_TOKEN (how the dashboard hands it
# to you); fall back to sops for the reproducible re-flash path.
TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-$(sops --decrypt --extract '["cloudflare_tunnel_token"]' "$SECRETS")}"

ssh "$HOST" 'sudo tee /var/lib/cloudflared.env >/dev/null && sudo chmod 600 /var/lib/cloudflared.env && sudo systemctl daemon-reload && sudo systemctl restart cloudflared-tunnel.service' <<EOF
TUNNEL_TOKEN=$TOKEN
EOF

echo "provisioned cloudflared.env onto $HOST and started the tunnel"
