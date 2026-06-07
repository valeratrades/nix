# Slow `shutdown now` — minutes-long hang, often needs hard power-off

## Symptom
`shutdown now` (and reboot) takes an ungodly amount of time. Almost always ends
with manually pressing the power button. Black screen / no progress, then nothing.

> **2026-06-06 FINAL — root cause is a tmux↔systemd cgroup bug. SOLVED in v3.**
> Two earlier theories were WRONG and are kept below only for the record:
>   - (2026-06-05) late `systemd-shutdown` unmount phase — disproved by debug capture.
>   - (2026-06-06 v2) "nvim ignores SIGTERM" — disproved by direct testing: nvim
>     exits in <10ms on SIGTERM in every scenario (dirty buffer, real tmux TUI, even
>     sitting at a blocking confirm() prompt). nvim was just the usual *occupant* of
>     the affected panes, not the cause.
> ACTUAL cause: tmux (built `withSystemd=true`) puts each pane in its own
> `tmux-spawn-*.scope`, but the scope creation FAILS ("Couldn't move process …
> Permission denied", 319+ times in the journal). The half-created scope is in a
> broken cgroup state, so systemd's `KillMode=control-group` SIGTERM never reaches
> the process at shutdown → the scope rides out its stop timeout → SIGKILL.
> Fix: build tmux WITHOUT systemd (v3 below). See "ROOT CAUSE FOUND" + "v3".

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

### ROOT CAUSE FOUND (2026-06-06) — it was NOT the late systemd-shutdown phase
The debug capture (v1 #3) did its job. Comparing two boots:

- **Boot -2 (Jun 05 16:55, CLEAN/FAST):** full `systemd-shutdown` sequence runs in
  seconds — sync, swap off, EXT4 unmount, "Sending SIGTERM to remaining processes",
  power off. This is what healthy looks like. The late phase is FINE.

- **Boot -1 (Jun 06 03:43, THE SLOW ONE):** never even reaches `systemd-shutdown`.
  It's stuck *earlier*, in the **user manager** (`user@1000.service`) waiting on a
  tmux pane, counting against the 90s timeout:
  ```
  user@1000.service: Got notification message from PID 1839: STATUS=User job
    tmux child pane 49603 launched by process 15346/stop running (28s / 1min 30s)...
  ```
  It ticks up every 0.5s from 2s toward the full `1min 30s` before SIGKILL.

**The blocker is nvim inside tmux panes.** History confirms it's recurring — the
`tmux-spawn-*.scope` units consistently time out and get force-killed, and the
process inside is `nvim` every time (nvim traps/ignores SIGTERM, e.g. unsaved
buffers / its own signal handling, so the scope rides out the full timeout):
```
May 29 / May 30 (x2) / Jun 03 / Jun 05:
  tmux-spawn-….scope: Stopping timed out. Killing.
  tmux-spawn-….scope: Killing process … (nvim) with signal SIGKILL.
```

**Why v1's 15s cap didn't fix this:** `systemd.settings.Manager.*` only writes
`system.conf` (PID-1 units). The user manager reads a SEPARATE file, `user.conf`,
which still had the 90s default. Confirmed at diagnosis time:
`systemctl --user show -p DefaultTimeoutStopUSec` → `1min 30s`.

### CORRECTION (2026-06-06) — v2's nvim premise was WRONG, real cause found
The v2 entry below assumed nvim ignores SIGTERM. Direct testing disproved it:
spawned real nvim with an unsaved buffer in a real tmux TUI, sent SIGTERM, measured
exit time. Result: **<10ms in every case** — dirty buffer, real TUI, even sitting at
a blocking `confirm()` prompt. nvim's built-in SIGTERM handler is robust. A nvim-side
`Signal`/`qall!` handler was prototyped and then REVERTED (wrong target).

Re-reading the journal for the scope that actually held back `shutdown.target`
(`tmux-spawn-b6884f31…`) revealed the real mechanism:
```
17:20:23 …b6884f31.scope: Couldn't move process 49603 to directly requested cgroup
         '…/tmux-spawn-b6884f31….scope': Permission denied
17:20:23 …b6884f31.scope: 1 process added to scope's control group.
…
03:43:02 …b6884f31.scope: Changed running -> stop-sigterm
03:43:02 shutdown.target: starting held back, waiting for: …b6884f31.scope
         (then total silence from the process until SIGKILL — SIGTERM never landed)
```
- `KillMode=control-group`, `KillSignal=15` — systemd signals the *cgroup*.
- tmux 3.6a in nixpkgs is linked against `libsystemd` (`withSystemd=true`), so it
  creates a per-pane scope and tries to move the pane process into that cgroup.
- That move FAILS with "Permission denied" (319+ times across all boots). The scope
  ends up half-created; systemd's control-group SIGTERM can't deliver. The process
  sits untouched until the timeout's final SIGKILL.
- nvim never even received the signal — hence it couldn't have been an nvim problem.

### v2: cap the USER manager too (2026-06-06) — APPLIED, verified live
(Kept as a defensive backstop — caps ANY hung user unit at 15s — but it is NOT the
real fix; it only bounded the symptom. v3 removes the cause.)
Added to `os/nixos/configuration.nix` systemd block:
```nix
systemd.user.extraConfig = ''
  DefaultTimeoutStopSec=15s
'';
```
Verified live after switch: `systemctl --user show -p DefaultTimeoutStopUSec` → `15s`,
and `/etc/systemd/user.conf` `[Manager]` has `DefaultTimeoutStopSec=15s`.
Worst case is now ~15s instead of 90s for any hung user unit.

NB on the switch: `nixos-rebuild` initially failed on an UNRELATED pre-existing
breakage — an uncommitted `flake.lock` bump (`btc_line` → a rev that needs the local
`/home/v/s/v_exchanges` Rust workspace, which fails `cargo` workspace resolution).
Stashing `flake.lock` (committed HEAD builds clean) let the shutdown fix land; the
WIP lock change was restored afterward. That breakage is tracked separately, not here.

### v3: build tmux without systemd (2026-06-06) — APPLIED, fix verified by test
THE actual fix. In `hosts/hm-shared/home.nix`:
```nix
programs.tmux.package = pkgs.tmux.override { withSystemd = false; };
```
Without `libsystemd`, tmux stops creating per-pane scopes; panes become plain
children of the tmux server, which systemd kills cleanly as one cgroup.

Verified:
- Overridden tmux has NO libsystemd (`ldd … | grep systemd` → empty).
- Direct test: started a new tmux server with the new binary, spawned a pane,
  counted `tmux-spawn-*.scope` units before/after → UNCHANGED (no new scope), and
  zero new "Permission denied" lines in the journal. The bug's trigger is gone.

Caveat: the tmux server RUNNING at switch time is still the old systemd-linked
binary (22 stale scopes remain). Restart the tmux server (or reboot) to fully clear.
New servers are clean from now on.

## TODO
1. ~~Trigger a slow shutdown to capture the culprit~~ DONE.
2. ~~Confirm root cause~~ DONE — tmux↔systemd per-pane scope cgroup failure, NOT nvim.
3. ~~Real fix~~ DONE — v3, tmux `withSystemd=false`, verified by test.
4. **Restart the running tmux server (or reboot)** to drop the 22 stale
   systemd-linked scopes from the old binary. After that, do one normal
   `shutdown now` to confirm it's instant.
5. **Remove the `systemd.log_level=debug` `#dbg` kernel param** in
   `os/nixos/configuration.nix` — diagnostic only, noisy. (Keep until #4 confirms.)
6. Optional cleanup once confirmed fixed:
   - `systemd.shutdownRamfs.enable` (v1 #2) — late phase was never the problem; removable.
   - the 15s `DefaultTimeoutStopSec` caps (v1 #1, v2) — worth KEEPING as a cheap
     defensive backstop against any future hung unit. Recommend leaving them.

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
