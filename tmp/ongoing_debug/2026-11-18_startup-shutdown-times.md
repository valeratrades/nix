# Startup / shutdown times

**Startup**: power button → first terminal window (alacritty) open.
**Shutdown**: `shutdown`/`poweroff` run → laptop off past the point where a keypress or lid open/close can wake it.
---

History: [2026-10-18_slow-boot.md](2026-10-18_slow-boot.md) (measured to Chrome's tab instead, firmware findings),
[2026-06-05_slow-shutdown.md](2026-06-05_slow-shutdown.md) (tmux scopes, mt7925 teardown, the 15s stop caps).

Measure: `journalctl --user -t boot-timeline` → `power→terminal=` (home/scripts/boot_timeline.mjs). Shutdown: gap between
`System is powering down` and the last journal line of `journalctl -b -1 -o short-monotonic`.

## Startup, boot d34cbeeb (2026-11-18 15:51), ≈19.1s
```
0        6.1  6.4 7.0   9.5   15.2 15.5      18.6 19.1                                    ~86
|firmware|ldr|krnl|initrd|systemd|getty|sway init|session→alacritty                         |
                                  ▲ terminal reachable here; below ran alongside, none blocks it
                                  ├ home-manager-v 72s (configureOpenclaw 70s: 5 node CLI calls)  ✂ skipped at boot
                                  ├ NetworkManager-wait-online 20.6s (holds tailscaled)           ✂ disabled
                                  ├ docker 4.1s (nothing uses docker)                             ✂ socket-activated
                                  ├ nvidia-persistenced 3.5s
                                  └ multi-user.target @79s = just HM finishing
```
Seconds since kernel start: getty 8.83, sway 9.12, sway-session.target 12.27, alacritty 12.70; + firmware 6.09 + loader 0.28.

The configureOpenclaw stamp includes the sops telegram token, unreadable at boot (sops decrypts on user session start),
so the stamp never matched at boot and it reran every boot, then again on the first switch after.

## Shutdown, last 5 boots
```
-1  3.5s
-2 23.4s  nix-daemon 2s cap · termfilechooser 15s (4153.7 → 4168.8)  ✂ KillMode=mixed + script reaps its nvim
-4  2.3s
-5  8.4s  /home unmount ~2.7s (writeback)
```
termfilechooser: a file chooser's nvim (pid 154302) outlived its window inside the portal's cgroup for an hour (471M peak,
16.5s CPU) and ignored SIGTERM at stop. KillMode=mixed SIGKILLs leftovers once the portal itself exits.
Repro guess: chooser window closed 3s after opening (log: OPEN ABORTED 12:47:12), nvim kept running. termfilechooser.sh now SIGKILLs it when alacritty returns and logs "reaped nvim" to ~/.local/state/termfilechooser.log.

Fixed alongside: nvidia-drm-late.path's implicit Before=paths.target made a stop-ordering cycle with logind
(systemd deleted logind's stop job every shutdown).

## Remaining levers
- firmware 6.1s: Fast Boot already Enabled (hidden menu, see 2026-10-18 file). PXE Boot to LAN → Disabled is the one left: BIOS menu only (firmware rejects runtime `Setup` writes), steps in issue #21.
- sway init ~3.2s (sway → sway-session): see 2026-10-18 Sway section. eDP seamless modeset: issue #30. One-boot sway timings: `smart_shutdown --debug-next-boot`.
- usb1-port1 "Cannot enable" at shutdown is the Redmi Note 14 (RNDIS tethering) re-enumerating after its link drops. Kernel hub retries, nothing waits on them: not on the shutdown path.

## Not yet verified on a real boot (applied via `nixos-rebuild boot` 2026-11-18)
configureOpenclaw boot skip, wait-online off, docker on demand, termfilechooser KillMode, nvidia path cycle,
boot-timeline `power→terminal` + chrome_exec no longer crashing the script (Chrome dropped the histogram).
