#!/usr/bin/env bash
# PreToolUse(Bash): an agent's full-tunnel VPN took the whole host offline twice, see ~/nix/tmp/ongoing_debug/2026-09-27_host-network-blackhole-warp.md
cmd=$(jq -r '.tool_input.command // empty')
if grep -qE 'wg-quick +up|warp-cli +(connect|--accept-tos +connect)|ip( -[46])? +route +(add|replace|change) +(default|0\.0\.0\.0/0|::/0)|tailscale +(up|set) .*--exit-node=[^ ]|openvpn +--config|nmcli .*connection +up' <<<"$cmd"; then
  echo "Blocked: this changes the host's routing for every process (the user's browser and all agent sessions). Confine the tunnel to a network namespace (ip netns exec) or a proxy only your process uses, or ask the user to run it themselves." >&2
  exit 2
fi
