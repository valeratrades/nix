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

**Superseded 2026-09-01 by `2026-09-01_kernel-7.1-fan-lever.md`.** The lever exists:
`lenovo-wmi-other` (kernel ≥7.0) registers a `lenovo_wmi_other` hwmon with RW
`fanN_target`, issued with thermal mode `NONE`, i.e. independent of `platform_profile`.
"Moving to a newer kernel is not known to deliver the drivers" is likewise retracted.

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

## 2026-09-01: reopened — §4 was right about the cost, wrong about the cause

### The coupling is real, and it was never measured before
Measured here for the first time. 24 spinner threads, `boost=0`, `scaling_max_freq=2501000`
(i.e. exactly what `optimize_for longevity` sets), amdgpu `power1_input` as the package
power proxy:

| `platform_profile` | `powermode` | avg core clock | package power |
|---|---|---|---|
| `quiet` | 1 | **527 / 701 MHz** | 33 W |
| `performance` | 3 | **1955 / 1956 MHz** | 40–41 W |

Two runs each, interleaved. `longevity` is paying **+8 W and a 3× clock envelope** for its
fan curve. §4's cost claim stands.

NB: peak-power-over-a-window is a useless metric here — an earlier pass using it showed the
profiles as indistinguishable. Average core clock under sustained load is the discriminator.

### But "no other fan lever exists" was a wrong inference from a broken driver
`legion_laptop` has no entry for this machine and is force-loaded:

```
legion PNP0C09:00: is_denied: 0; is_allowed: 0; do_load_by_list: 0; do_load: 1
legion PNP0C09:00: legion_laptop is forced to load and would otherwise not be loaded
legion PNP0C09:00: Using configuration for system: GKCN      <-- wrong model's EC register map
legion PNP0C09:00: Read embedded controller ID 0x5508
legion PNP0C09:00: Skipped checking embedded controller id
```

This is a **Legion R9000P ADR10** (`83LV`, BIOS `RLCN29WW`, 08/2025, Ryzen 9 8945HX).
`GKCN` is a 2021-era Legion. Every EC-mediated knob is consequently reading and writing
garbage addresses:

| interface | observed | verdict |
|---|---|---|
| `fan1_input` / `fan2_input` | frozen at 23135 / 18020 for 45+ min, vs `fan1_max` 10000 | latched, not live |
| `pwm1_auto_pointN_pwm` | 150, 0, 145, 5, 163, 0… all temps 0 | non-monotonic, not a curve |
| `legion_hwmon` GPU temp | fixed 87 °C while `nvidia-smi` read 59 °C | latched |
| `fan_fullspeed` write | accepted, reads back 0 | no effect |
| `legion_cli maximumfanspeed` | enable succeeds, status False | no effect |
| `platform_profile` | `powermode` tracks 1/2/3, behaviour changes (table above) | **works — it is ACPI, not EC** |

So `maximumfanspeed` was never a fair test of "can fans be pinned independently". It failed
because it wrote a GKCN offset to an RLCN EC. **We cannot presently observe fan RPM at all**,
which is the more serious problem: "fans max" in `longevity` is an assumption, not a
measurement.

### The untapped lever: this firmware exposes the full Lenovo WMI interface
All four GUIDs the upstream `lenovo-wmi-*` drivers bind are present in `/sys/bus/wmi/devices/`:

| GUID | upstream driver | bound here |
|---|---|---|
| `887B54E3-DDDC-4B2C-8B88-68A26A8835D0` | `lenovo-wmi-gamezone` | `legion_wmi` (out-of-tree) |
| `DC2A8805-3A8C-41BA-A6F7-092E0089CD3B` | `lenovo-wmi-other` — **PPT tunables** | none |
| `7A8F5407-CB67-4D6E-B547-39B3BE018154` | `lenovo-wmi-capdata01`, `instance_count=70` | none |
| `D320289E-8FEA-41E0-86F9-911D83151B5F` | `lenovo-wmi-events` | none |

Kernel is 6.12.85 LTS; those drivers landed in 6.15. `CONFIG_LENOVO_WMI_CAMERA=m` is the only
one built. `lenovo-wmi-other` exposes `ppt_pl1_spl` / `ppt_pl2_sppt` / `ppt_pl3_fppt` through
the firmware-attributes class, which this kernel does **not** build:

```
$ gunzip -c /proc/config.gz | grep -E 'FIRMWARE_ATTRIBUTES_CLASS|DELL_WMI_SYSMAN'
CONFIG_DELL_WMI_SYSMAN=m          <- and nothing else; the class symbol is absent
```

(An earlier draft of this section claimed `DELL_WMI_SYSMAN` selects the class on 6.12. It does
not. The class is one more thing a backport has to carry.)

That is the decoupling: keep `platform_profile=performance` for the fan curve, then clamp PPT
back to `quiet`-equivalent through WMI. Both knobs, one path, no EC register archaeology.

### Route, in preference order

1. **Backport `lenovo-wmi-capdata01` + `lenovo-wmi-other` to 6.12** as an out-of-tree module.
   These two do not touch `platform_profile`, so they sidestep the one real backport hazard:
   `lenovo-wmi-gamezone` needs the multi-handler `platform_profile_register()` API added in
   6.14, which 6.12 does not have. Skipping gamezone means keeping ACPI `platform_profile` as
   the fan lever — which is fine, that is the part that already works.
2. **Move to kernel ≥6.15.** ~~6.15/6.16/6.17 were never tried.~~ **They do not exist to try.**
   All four of 6.15, 6.16, 6.17 and 6.19 are EOL upstream and removed from this nixpkgs — they
   survive only as `throw` aliases, which is why they still appear in `builtins.attrNames`:

   ```
   linuxPackages_6_15 = throw "linux 6.15 was removed because it has reached its end of life upstream";
   ```

   The real menu is **6.12.100 (current), 6.18.41, 7.1.5** — and 6.18 is precisely the one
   `configuration.nix:147` records as breaking the nvidia driver. So the "just move to a kernel
   that has the drivers" route means 7.1.5, which nothing here has ever booted.
3. **`ryzenadj`** — identifies this CPU as Dragon Range and can write SMU limits via `/dev/mem`,
   but `request_table_ver_and_size is not supported on this family`, so limits cannot be read
   back. Setting power limits blind, with no verification, against a `platform_profile` that is
   also writing them. Rejected unless 1 and 2 both fail.
4. **Add an `RLCN` entry to `legion_laptop`'s model table.** Requires reverse-engineering this
   EC's register layout from scratch. Highest effort, and it buys the fan curve back — worth
   doing only if fan *observability* turns out to matter more than PPT control.

### Not proven
- That the fans are actually at maximum in `performance`. Unmeasurable until an interface that
  can read RPM exists. The whole justification for `platform_profile=performance` rests on it.
- That `lenovo-wmi-other`'s methods behave on this firmware. The GUID is present; nothing has
  called it. Requires the driver to test.
- Whether `powermode`/`thermalmode` (WMI, working) expose a fan-speed method independent of the
  profile. The BMOF that names these methods is `DS`-compressed and `bmfdec` is not in nixpkgs;
  the DSDT names them `WMAA`-style, so it carries no friendly names.
- **Whether nixpkgs enables `CONFIG_LENOVO_WMI_*` on 6.18 or 7.1 at all.** Attempted via
  `kernel.config.isEnabled`; that returned empty for every symbol including ones known to be
  `=m` on the running kernel, so the query is broken and produced no data. A first pass read
  those empties as `false` — they mean nothing. Unanswered. Until it is answered, "move to a
  newer kernel" is not known to deliver the drivers even on a kernel that upstream ships them in.
- Whether upstream `lenovo-wmi-gamezone` can coexist with the out-of-tree `legion_laptop`. Both
  bind `887B54E3-…` (it is currently claimed by `legion_wmi`) and both register a
  `platform_profile` handler. Untested; a likely conflict on any kernel that has both.

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
