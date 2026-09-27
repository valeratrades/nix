# Whole host loses network. Every LLM session, the browser, and MCP logins hang, and only a reboot recovers it

Status: **root cause found.** A guard hook is in place. Move this file to `solved/` if no new incident happens by ~2026-10-11.

## Cause

An agent in `~/s/ev_invest/_service_arb/emulate_phone_cam` (session `e2fb3ac5`) wanted in-region egress for the emulator. It ran this on the **host**:

```
cd ~/.local/state/warp && sudo wg-quick up ./warp.conf   # wgcf profile, AllowedIPs = 0.0.0.0/0, ::/0
```

wg-quick with a /0 peer installs `table 51820` + `not fwmark 51820` + `suppress_prefixlength 0` rules at priority 5208/5209, ahead of tailscale's `lookup 52` at 5270, so every packet on the host goes through `warp` — MagicDNS's 100.100.100.100 included, which then hung every lookup. WARP itself passes traffic: the same profile, moved into a netns, exits at 104.28.x (loc=FR). Nothing ran `wg-quick down`, and the interface stayed up until the reboot.

| incident | `wg-quick up` | reboot |
|---|---|---|
| 1 | 2026-09-26 14:31:20 | boot ended 15:07 |
| 2 | 2026-09-27 09:50:25 | 10:07 (manual poweroff) |

## Cascade (incident 2)

```
09:50:25  sudo wg-quick up (no TTY → agent)      tailscaled: LinkChange, warp iface, table 51820
09:50:30  tailscale DERP rebind-ping-fail
09:50:41  nsncd: "timed out waiting for an available worker" → restarts (8 workers all stuck)
          resolv.conf = 100.100.100.100 (MagicDNS) → upstream 8.8.8.8/1.1.1.1 via warp → hangs
09:52+    tailscale control long-poll timeouts, repeating every ~2 min
          nsncd crash-loops every 1–4 min until the reboot
```

The Claude Code symptoms ("Remote managed settings failed to load", `API error · Retrying`, the MCP OAuth stall) are all downstream effects. The TUI is not involved.

## How to confirm the next time

- `ip link show warp` / `ip rule` shows `lookup 51820` → it is this bug again. Fix it live with `sudo ip link del warp` (that drops wg-quick's rules' target; then `sudo ip rule del table 51820` until `ip rule` is stock), no reboot needed. `~/.local/state/warp/` no longer exists: the profile is `~/.local/state/emulate_android/egress/warp.conf`, and emulate_android now only ever brings it up inside netns `emulate_android` (`egress down` removes it).
- `journalctl -b -1 | grep -E 'sudo\[.*COMMAND=|nsncd.*worker'`. A sudo line with no `TTY=` came from an agent.
- To find the session: `grep -rl '<command fragment>' ~/.claude/projects`.

## Guard

The PreToolUse hook `home/config/claude/hooks/no_host_route_hijack.sh` blocks `wg-quick up`, `warp-cli connect`, `ip route add default`, `--exit-node=`, `openvpn --config`, and `nmcli connection up` in every Claude session. The emulator egress must be confined to a netns or a proxy.
