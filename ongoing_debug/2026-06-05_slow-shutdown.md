# Slow `shutdown now` — minutes-long hang, often needs hard power-off

## Symptom
`shutdown now` (and reboot) takes an ungodly amount of time. Almost always ends
with manually pressing the power button. Black screen / no progress, then nothing.

## Investigation (2026-06-05)

### Persistent journal is blind to the actual stall
`/var/log/journal` is persistent, so we *do* have past-boot logs. But the captured
shutdown sequence always ends **cleanly** (last lines are units stopping, no timeout
message). The reason: the journal stops writing once the root FS is remounted
read-only. The real hang lives **after** that point, in the late `systemd-shutdown`
phase (leftover-process SIGKILL → final unmount/detach → disassemble dm/loop/swap),
which never reaches persistent storage. That's exactly why the logs look innocent.

### Postgres SIGKILL was a red herring
Across 20+ boots the journal shows, every single shutdown:
```
postgresql.service: Killing process … (.postgres-wrapp) with signal SIGKILL.
```
Looked like a 90s `TimeoutStopSec` hang. It is NOT. Postgres's own log proves a
clean sub-second shutdown:
```
[2397] LOG:  received fast shutdown request
[2397] LOG:  aborting any active transactions
[2469] LOG:  checkpoint complete: ... total=0.010 s
[2397] LOG:  database system is shut down
```
On boot -1 the whole `postgresql.service` stop took **25 ms** (46.781 → 46.808).
The SIGKILL is systemd reaping an already-dead cgroup remnant (`KillMode=mixed`,
`KillSignal=SIGINT`, `Type=notify`). **Postgres is innocent.**

### Live state — no obvious detach hang
At inspection time: `docker` mounts = 0, swap is a plain partition (`/dev/nvme0n1p5`),
fuse connections = 3. The hang-prone surface in the final phase is the **fuse mounts**:
- `envfs` on `/bin` and `/usr/bin`
- `gvfsd-fuse` on `/run/user/1000/gvfs`
- xdg `portal` on `/run/user/1000/doc`

Nothing in the live snapshot screamed a guaranteed 90s detach, so the stall is likely
intermittent / depends on what's running at shutdown time. This means it has to be
**captured live** rather than inferred from the (blind) persistent journal.

## What it was NOT
- **Not postgres** — clean sub-second shutdown, see above.
- **Not docker leftover mounts** — 0 docker mounts at inspection.
- **Not swap teardown** — plain partition, not zram/file.
- **Not the firewall `extraStopCommands`** — trivial `iptables -D … || true`.

## Mitigation history

### v1: cap + capture (2026-06-05) — APPLIED, NEEDS A REAL SLOW SHUTDOWN TO CONFIRM
All in `os/nixos/configuration.nix`, applied via `nixos-rebuild switch` and verified live:

1. `systemd.settings.Manager.DefaultTimeoutStopSec = "15s"`
   Hard floor so no single hung unit can ever eat the 90s default again.
   Verified live: `DefaultTimeoutStopUSec=15s` (was `1min 30s`).
   (Precedent: clickhouse `TimeoutStopSec = 5` cap in `shared-services.nix`.)

2. `systemd.shutdownRamfs.enable = true`
   Pivots to a clean ramfs for the final unmount/detach phase — fixes many
   fuse / lazy-unmount stalls on its own. Verified: `generate-shutdown-ramfs.service`
   is `enabled`.

3. `systemd.log_level=debug` kernel param (marked `#dbg`, "remove once found")
   Makes the late `systemd-shutdown` phase log the stuck step to the **console**.
   Correctly absent from current `/proc/cmdline` — applies on the *next* boot's
   shutdown. Present in the new boot entry.

## TODO
1. **Trigger a normal `shutdown now`.** If still slow, the console now names the
   stuck step (watch the screen, or read it after with
   `journalctl -b -1 -o short-precise | tail -60`, grep `systemd-shutdown`).
2. If the culprit is a fuse mount, the most likely fixes:
   - ensure the owning service has `Before=umount.target` ordering / lazy unmount, or
   - cap that unit's stop, or
   - if `shutdownRamfs` already fixed it, just confirm and move on.
3. **Once fixed: remove the `systemd.log_level=debug` `#dbg` kernel param** in
   `os/nixos/configuration.nix` — it's diagnostic only.
4. Consider whether the 15s `DefaultTimeoutStopSec` floor is too aggressive for any
   legit slow-stopping service (none known so far).

## NB — cross-reference
The hard power-offs caused by THIS bug are the source of the accumulating
"unsafe shutdowns" count on both NVMe drives (175 noted in
`2026-03-26_amd-vi-iommu-stall.md`). Fixing this directly reduces FS-corruption risk.

## Hardware / config context
- Host: `v-laptop` (Lenovo Legion, Ryzen 8840U + RTX 5060)
- Kernel: `linuxPackages_6_12` (6.12 LTS)
- systemd: 260.1
- Hardware watchdog: `wdat_wdt`, 10min timeout (this is the normal systemd-shutdown
  safety net, NOT the cause — it arms on every clean shutdown).
