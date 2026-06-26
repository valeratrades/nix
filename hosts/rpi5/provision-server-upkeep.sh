#!/usr/bin/env bash
# Push the server_upkeep telegram secret onto the RUNNING rpi5.
#
# server_upkeep's systemd unit reads its secrets from /var/lib/server_upkeep.env
# (config-rs picks up the SERVER_UPKEEP__* vars; precedence env < file < flags).
# That file is the ONLY place the bot token lives — never in the repo or store —
# exactly like the wifi secret. The unit has ConditionPathExists on it, so it
# stays inactive until this script has run; afterwards a daemon-reload + start
# brings it up.
#
# Source of truth is sops (secrets/users/v/default.json). Add the two keys first:
#   sops secrets/users/v/default.json
#     "telegram_main_bot_token": "123456:ABC...",
#     "telegram_alerts_channel_id": "-100123456789"
#
# Idempotent. Usage: ./provision-server-upkeep.sh [SSH_HOST]   (default: admin@rpi5.local)
set -euo pipefail

HOST="${1:-admin@rpi5.local}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS="$HERE/../../secrets/users/v/default.json"

TOKEN="$(sops --decrypt --extract '["telegram_main_bot_token"]' "$SECRETS")"
CHAT="$(sops --decrypt --extract '["telegram_alerts_channel_id"]' "$SECRETS")"

# write 0600 root:root, then (re)start the unit so it picks up the new secret
ssh "$HOST" 'sudo tee /var/lib/server_upkeep.env >/dev/null && sudo chmod 600 /var/lib/server_upkeep.env && sudo systemctl daemon-reload && sudo systemctl restart server_upkeep.service' <<EOF
SERVER_UPKEEP__TELEGRAM__BOT_TOKEN=$TOKEN
SERVER_UPKEEP__TELEGRAM__ALERTS_CHAT=$CHAT
EOF

echo "provisioned server_upkeep.env onto $HOST and restarted the service"
