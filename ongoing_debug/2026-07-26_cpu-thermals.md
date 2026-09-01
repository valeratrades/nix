# CPU pinned at 90°C with fans at max — thermal management was mostly inert

Status: **changes applied 2026-07-26, awaiting a rebuild + a few days of monitoring.**
Two `#TEST` kernel-param changes here need watching; see "Watch list" at the bottom.

## Symptom

Laptop sat at 84–91°C with both fans at max, seemingly whenever a video played.
Journal showed `thermal-guard` flapping every few minutes, all night:

```
02:59:01  Throttling: 90C >= 90C
03:01:49  Restored: 79C < 80C
03:06:31  Throttling: 90C >= 90C     <- and so on
```

The initial suspicion (too many rust-analyzer / Claude instances, or a video in
Firefox) was only a third right, and the mechanism was not what it looked like.

## What was actually wrong — five separate things

### 1. CPU boost was never the problem — it had been off since boot
`legion-longevity.service` writes `boost=0` at every boot. Verified live: all 32
policies capped at the 2501 MHz base clock, every core measured at ~2475 MHz, and
`amd_pstate_max_freq` (5461 MHz) unreachable. **Nothing had boosted all session**,
yet the machine still hit 91°C. Boost caps the *ceiling*; it does nothing to stop
16 cores sitting at that ceiling indefinitely.

### 2. `thermal-guard`'s throttle was a ~4% no-op
```nix
FREQ_THROTTLE=2400000  # ~44% of max
```
That constant was written against the **boost** clock (5461 MHz). With boost off,
`cpuinfo_max_freq` is 2501 MHz — so "throttling" cut 2501 → 2400 MHz. The
temperature barely moved, so it un-throttled and immediately re-triggered. That is
the whole explanation for the flapping above.

Fixed: the throttle target is now read from `cpuinfo_max_freq` at runtime.

### 3. `processor.max_cstate=1` blocked every deep idle state
Confirmed by inspection — `cpu0` offered only `POLL` and `C1`, no deeper state at
all. C1 gates the clock but keeps voltage and caches, so all 32 threads leaked
power continuously even at idle. This is the likely dominant cause of the *idle*
temperature. See §"Watch list".

### 4. BUG!!!!!!! — `platform_profile` couples fans to power limits *(REOPENED 2026-09-01)*
`longevity` mode was setting `platform_profile=performance` **purely to get the
fans up** — but on this EC that same knob also raises PPT/STAPM. So "longevity"
was licensing the CPU to draw *more* power. The name was backwards.

`legion_cli maximumfanspeed` is the documented way to pin fans independently.
**It does not work on this firmware**: `maximumfanspeed-enable` returns success and
`maximumfanspeed-status` still reads `False`, in every profile. Tested directly.

**The 2026-07-26 conclusion — "the PPT increase is the unavoidable price of airflow"
— was wrong, or at least unproven.** It surveyed exactly one alternative lever
(`maximumfanspeed`) and generalised from its failure to "no lever exists". The
requirement is not negotiable: `optimize_for longevity` must deliver max fans AND
zero boost at the same time. Under investigation as of 2026-09-01 — see
"2026-09-01: reopened" below.

### 5. Firefox was software-decoding every video
`user.gpuAcceleration = false` (`vars/default.nix`) gated VA-API decode *and*
forced GPU rendering behind one flag. `LIBVA_DRIVER_NAME` was absent from the
running Firefox's environ — every frame decoded on CPU. See
`firefox-gpu-acceleration.md` §"2026-07-26" for the correction.

## Measurements

Identical synthetic 32-thread load, boost off in both cases:

| `scaling_max_freq` | Tctl |
|---|---|
| 2501 MHz (uncapped) | **98.5°C** |
| 1375 MHz (55%) | **89.6°C** |

98.5°C with boost already off — the proof that boost-off was never a real limit.
(Tjmax is 100°C, so that run was ~1.5°C from hardware PROCHOT.)

### A standing frequency cap was tried and rejected
Capping to 55% full-time was implemented, then backed out. Under `schedutil`
(`scaling_min_freq` = 400 MHz) the cores already scale with demand, so a standing
cap does nothing for browsing and only penalises compiles — the one workload that
is supposed to be fast. Throttling is now purely reactive, on measured heat.

## Changes applied

- `services/thermal.nix`
  - throttle target computed from the live ceiling, not a hardcoded constant
  - thresholds 90°C → 85°C trip, 80°C → 75°C release (user preference)
  - `thermal-guard` no longer writes `platform_profile` **at all** — it previously
    hardcoded `balanced` on restore, so a single thermal excursion silently
    downgraded whatever mode the user had chosen
  - `power-profiles-daemon` disabled (it was a third writer racing for
    `platform_profile`; nothing consumed its D-Bus API). It was *also* enabled in
    `services/graphics.nix`, so removing one line was not enough.
  - the "never allow quiet profile" block is gone with the daemon that motivated it
- `configuration.nix` — `processor.max_cstate=1` and `amd_pstate=passive` removed,
  `pcie_aspm.policy=performance` kept with its trade-off documented
- `home/scripts/optimize_for.rs` — modes rebuilt around the real knobs; added a
  scoped form, `optimize_for performance -- cargo b`, that boosts for the duration
  of a command and restores after
- `hosts/hm-shared/nixcord.nix` — Discord no longer minimises to tray (below)

### Arbitration primitive: `/run/optimize_for.base-freq`
`scaling_max_freq` legitimately has two writers (the declared mode, and
`thermal-guard`'s temporary excursions). The file holds exactly one thing: the
frequency this machine should sit at when *not* thermally stressed. Written by
whoever declares a mode, read by `thermal-guard` so it restores the declared
baseline instead of inventing one. Without it, the first hot spell would silently
undo a chosen cap by "restoring" to the hardware ceiling.

`platform_profile` needed no such primitive — it was fixed by *removing* writers
until only one remained.

## Not the cause (retracted)

- **rust-analyzer** — 1m13s and 1m26s of CPU over 2.9h and 7.4h. Idle. Costs 2.1 GB
  of RAM and essentially no CPU. There are 2 servers + 2 `proc-macro-srv` helpers,
  not 4 servers.
- **Repaste / dust** — battery at 152 cycles, machine is young.
- **dGPU** — ~~10.7 W / 60°C at idle is real heat in a shared chassis, but
  `hardware.nvidia.powerManagement.finegrained` is deliberately off (D3cold wedges
  the 5060 on this SBIOS). Left alone.~~
  **REOPENED 2026-09-01 — see `2026-09-01_dgpu-lit-by-hdmi.md`.** Two claims here
  are wrong. (a) finegrained is not why it is awake: the HDMI port is wired to the
  dGPU, which is therefore the only active display controller whenever the external
  monitor is plugged in — ~9.7 W, a quarter of system power, unavoidable in software.
  (b) `finegrained = false` does not disable driver-side RTD3 anyway
  (`DynamicPowerManagement: 3`, driver reports `Enabled (fine-grained)`); it only
  omits the udev rule, leaving `power/control=on` → `runtime_enabled: forbidden`,
  so the dGPU never suspends even *unplugged*. The D3cold-wedge attribution is
  unverified, not disproved.

## Discord — 32% of a core, in the background

PID 14672: **3h11m of CPU over 9.9h elapsed** while "closed" to the tray.
`programs.nixcord.discord.settings.MINIMIZE_TO_TRAY = false` so closing quits.

NB: nixcord **copies** rather than symlinks `settings.json`, clobbering it on every
activation — so that attrset is the entire file, and anything omitted is lost.
Window bounds will reset on each rebuild.

The ~32% burn *while the window is open* is a separate, undiagnosed Electron issue.

## Watch list

1. **`processor.max_cstate=1` removal** — biggest revert risk. If AMD-Vi
   Completion-Wait timeouts or hard lockups reappear, this is the first suspect.
   `journalctl -kf | grep -iE 'AMD-Vi|amdgpu'`. See
   `2026-03-26_amd-vi-iommu-stall.md`.
   **Two unlogged hard resets have since landed (08-03, 08-22), both after this
   removal, neither with an AMD-Vi timeout.** Circumstantial, not acted on. See
   `2026-08-22_unlogged-hard-reset.md`.
2. **`amd_pstate=active`** — was `passive` "for stability", but no doc ever recorded
   what that instability was. Watch for stalls or frequency misbehaviour.
3. **`pcie_aspm.policy=performance`** — still needed; retest once the kernel carries
   the mt7925 BT-disconnect fix (not in 6.12.85). See `2026-06-05_slow-shutdown.md`.
