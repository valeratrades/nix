# Hard reset with no trace anywhere — recurring

Status: **2 incidents, no cause identified.** Instrumentation is in place and has
ruled out the cheap explanations; the remaining candidates all sit below the kernel.

## Signature

The journal ends mid-line and the next boot begins ~30s later. No shutdown
sequence, no `Journal stopped`, no panic, no kernel message of any kind. Power was
cut *below* the kernel — nothing that runs on the CPU got a chance to speak.

Distinguishing it from every other failure class in this directory:

| | this | AMD-Vi stall | thermal shutdown | OOM freeze |
|---|---|---|---|---|
| journal end | mid-line | mid-line | mid-line | mid-line |
| precursor in log | **none** | `Completion-Wait loop timed out` | 90°C+ trip | oom-kill spam |
| recovery | reboots itself | needs manual hard reset | reboots itself | needs manual hard reset |
| pstore | empty | empty | empty | empty |

The self-reboot is the discriminator against the two lockup classes: nobody held
the power button, the machine came back on its own.

## Incidents

### 2026-08-22 09:16:29 — full sampler capture

`sensor-sampler` (added after the first incident, for exactly this) has the last
reading, 2 seconds before the cut:

```
09:16:17  cpu=81C igpu=0C ppt=0W dgpu=63/13.52 dram=72C fmax=2501MHz ac=1 batt=Not charging/0W load=3.97
09:16:22  cpu=80C igpu=0C ppt=0W dgpu=63/12.66 dram=72C fmax=2501MHz ac=1 batt=Not charging/0W load=3.97
09:16:27  cpu=80C igpu=0C ppt=0W dgpu=63/12.74 dram=72C fmax=2501MHz ac=1 batt=Not charging/0W load=4.05
09:16:29  <journal ends mid-line>
09:16:59  boot
```

Boot -1 ran 05:36→09:16 (3h40m). `thermal-guard` had been throttled 08:40→09:10
and released at 09:10:26 — so the six minutes before the cut were the *coolest and
quietest* stretch of the morning. Battery 77%, 16.5V, flat for 15 minutes on AC.

### 2026-08-03 — same signature, no sampler yet

Recorded only in the `thermal.nix` comment written at the time; the journal has
since rotated past it. What was established then: journal ends mid-line, pstore
empty, and `kernel.panic=0` means a panic would have *hung* rather than rebooted —
so a panic cannot explain a self-reboot. The two preceding hours were blank
because `thermal-guard` only logs on a threshold crossing. That blank is what
motivated `sensor-sampler`.

## What it was NOT (2026-08-22)

- **Not thermal** — 80°C, 10°C under the `thermal-guard` trip, and *falling* since 09:10.
- **Not load or a power spike** — load 4.05, dGPU 12.7 W, iGPU idle.
- **Not battery or a slow adapter sag** — `ac=1` throughout, 16506–16508 mV for 15 min.
- **Not a panic** — pstore empty, kernel log silent, `tainted=4096` (out-of-tree
  module only, i.e. `legion_laptop`). And `kernel.panic=0` would hang, not reboot.
- **Not OOM** — 47 GB available, swap untouched.
- **Not the disks** — both NVMe report 0 media errors, 0 error-log entries.

## Leading suspect: `processor.max_cstate=1` removal

`2026-07-26_cpu-thermals.md` removed `processor.max_cstate=1` (it was capping
`cpuidle` at POLL+C1 and costing ~74–80°C at idle) and left this on its watch list:

> **`processor.max_cstate=1` removal** — biggest revert risk. If AMD-Vi
> Completion-Wait timeouts **or hard lockups** reappear, this is the first suspect.

Removed 2026-07-26. First reset 2026-08-03, second 2026-08-22. Both after, none
before. A deep C-state (C6/C3) that the SoC fails to exit *is* a plausible
mechanism for a reset with no software trace: the core never returns, and the
platform resets rather than hangs.

Against it: two events in ~3.5 weeks is thin, the machine has since run two clean
sessions (08-23, 08-24) with the same config, and no `AMD-Vi` timeout has
accompanied either reset — which is the symptom that watch-list entry actually
predicted.

Do not revert on this evidence alone; the idle-temperature cost is large and was
measured, while this link is circumstantial. Revert if a third reset lands.

## Other candidates, unranked

- **EC / firmware fault.** BIOS is RLCN29WW on a Legion 83LV; never updated. AGESA
  and EC updates are the usual fix for spontaneous platform resets. This is the
  cheapest untried action.
- **VRM or DC-jack transient.** Faster than the 5s sampler cadence, so invisible to
  it by construction. `power_supply/BAT0/power1_input` reads 0 W on AC, so there is
  no adapter-side current reading available at all.
- **Machine check.** Was entirely unread until now — see below.

## Instrumentation

### `sensor-sampler` (2026-08-03, `thermal.nix`)
5s cadence, to journald. Delivered on 2026-08-22: flushed to within 2s of the cut
and ruled out four hypotheses at once. Query: `journalctl -b -1 -u sensor-sampler | tail`.

### `rasdaemon` (2026-08-22, `thermal.nix`, commit `ecb286b9`)
The one channel still unread. Persists machine checks to `/var/lib/rasdaemon`
across a reset and pulls the firmware BERT record on the next boot — the only place
a fault below the kernel can still leave a trace. Query: `ras-mc-ctl --errors`.

Clean as of 2026-08-27, but it has not yet seen an incident: it started *after* the
08-22 reset, and 08-23 / 08-24 both shut down normally. **It has not been tested by
the failure it was installed for.**

## Open thread: unsafe-shutdown count doesn't add up

| | 2026-03-31 | 2026-08-27 |
|---|---|---|
| nvme0 unsafe shutdowns | 175 | **254** |
| nvme1 unsafe shutdowns | 175 | **253** |

79 unsafe shutdowns in five months against 2 known hard resets in this class.
Either there are many more power cuts than we have noticed, or the normal shutdown
path is not quiescing the drives and every ordinary reboot counts as unsafe. The
second is far more likely and would mean the counter is useless as a crash proxy —
worth knowing either way, since `2026-06-05_slow-shutdown.md` is about that same
shutdown path.

Cheap test: note both counters, shut down cleanly, boot, re-read. If they moved,
the counter is noise. Baseline recorded above.

## Watch list

1. **A third reset** → revert `processor.max_cstate=1` first, and check
   `ras-mc-ctl --errors` *before* doing anything else.
2. **BIOS update** — RLCN29WW is the original. Untried, and cheap. (Also item 3 on
   `2026-03-26_amd-vi-iommu-stall.md`'s TODO, still open.)
3. **DRAM runs at 71–72°C** against a 55°C `spd5118` alarm threshold, continuously,
   for hours. Not implicated in either reset — it was 72°C for the whole session
   and the cut came during the *cool* stretch — but it is out of spec and unaddressed.
