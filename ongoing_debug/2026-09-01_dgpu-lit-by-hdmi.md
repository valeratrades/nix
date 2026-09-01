# dGPU burns ~9.7 W whenever HDMI is plugged — it is not "just lit", it is the display

Status: **investigated 2026-09-01, read-only. No changes applied. One finding
reopens the dGPU bullet in `2026-07-26_cpu-thermals.md`.**

## Symptom

Plugging the external Philips 27M2N3200AM keeps the RTX 5060 at 59–63 °C and
8–11 W indefinitely. `sensor-sampler` has logged **zero** `dgpu=off` samples in
10,735 samples across five boots (`-b` through `-b -5`). Expectation was that a
PRIME-offload dGPU idles at D3cold and only wakes for games/video.

## 1. The dGPU owns every external port on this machine. amdgpu owns none.

`/sys/class/drm/` enumeration is the whole answer to "can I just move the cable":

| connector | card | driver | status |
|---|---|---|---|
| `HDMI-A-1` | card1 | nvidia | **connected**, driving crtc-0 |
| `DP-1` | card1 | nvidia | disconnected |
| `DP-2` | card1 | nvidia | disconnected |
| `eDP-2` | card1 | nvidia | disconnected (MUX leg, see §5) |
| `eDP-1` | card2 | amdgpu | connected, DPMS **off** |
| `Writeback-1` | card2 | amdgpu | virtual, not a port |

`/sys/kernel/debug/dri/2/state` enumerates exactly two connectors on amdgpu —
`eDP-1` and `Writeback-1`. The AMD display engine has **one physical output on
this board, the internal panel**. HDMI-A-1, DP-1 and DP-2 (the USB-C legs) all
hang off `0000:01:00.0`.

This is a Ryzen 9 **8945HX** (`/proc/cpuinfo`) — Dragon Range, i.e. a desktop
Raphael die (`1002:164e`) in a laptop. Lenovo wired its two display lanes to
eDP and nothing else. **There is no port to move the monitor to.**

## 2. The internal panel is off, so amdgpu is scanning out nothing at all

`swaymsg -t get_outputs`:
```
eDP-1     : "power": false, "dpms": false
HDMI-A-1  : "power": true,  "active": true, 1920x1080@60
```
`/sys/class/drm/card2/device/gpu_busy_percent` = `0`.

The entire visible desktop is on the NVIDIA GPU. This is not offload degrading
gracefully — with the lid panel blanked, the AMD GPU is idle ballast and the
NVIDIA GPU is the only display controller in the system.

## 3. It is doing real work, not merely holding a device node open

Three separate proofs, in increasing strength:

**Scanout.** `/sys/kernel/debug/dri/1/state`:
```
plane[50]: plane-0
	crtc=crtc-0
	fb=149
		allocated by = sway
		format=AR24  modifier=0x300000000606014   <- NVIDIA block-linear
		size=1920x1080
		obj[0]: imported=no
crtc[61]: crtc-0  enable=1 active=1
	mode: "1920x1080": 60 148500 ...
connector[127]: HDMI-A-1  crtc=crtc-0
```
A native NVIDIA buffer (`imported=no`, NVIDIA-vendor modifier `0x03…`) on an
active CRTC. The display engine is running a real 148.5 MHz pixel clock.

**Render.** `nvidia-smi pmon` — `sway` is the only process, at 5–15 % SM:
```
# gpu   pid  type   sm  mem   command
    0  5139     G    9    0   sway
    0  5139     G   10    2   sway
    0  5139     G   15    4   sway
```
`/sys/kernel/debug/dri/1/clients` shows sway as DRM master on card1 *and*
holding three render contexts on `renderD128`. It composites HDMI-A-1 on the
NVIDIA renderer.

**Not a cross-GPU copy.** `nvidia-smi -q` PCIe: **Tx 750 KB/s, Rx 601 KB/s**. A
1080p60 ARGB stream copied from amdgpu would be ~498 MB/s — three orders of
magnitude more. Nothing is being blitted in from the iGPU; sway renders those
frames on the NVIDIA GPU directly.

So the answer to "is it actually doing anything": **yes — (a) scanout and
(b) compositing.** It is not idling with a stale file descriptor.

## 4. `power/control=on` means it can never runtime-suspend — monitor or not

`/sys/bus/pci/devices/0000:01:00.0/power/`:
```
control:               on
runtime_enabled:       forbidden      <- kernel will never runtime-suspend it
runtime_status:        active
runtime_usage:         2
runtime_active_time:   10299633 ms
runtime_suspended_time:      1254 ms   <- 1.25 s, in 2.9 h uptime
```

`runtime_enabled: forbidden` is unconditional. Even with the cable out and the
display engine dark, this device stays in D0 forever. **That, not HDMI, is why
five consecutive boots logged zero `dgpu=off` samples** — the sampler's
`dgpu=off` branch (`thermal.nix:165`) is dead code under the current config.

The driver's own view contradicts the nix config comment. `/proc/driver/nvidia/gpus/*/power`:
```
Runtime D3 status:          Enabled (fine-grained)
 Video Memory Self Refresh: Supported
 Video Memory Off:          Supported
Notebook Dynamic Boost:     Supported
S0ix Platform Support:      Not Supported
```
and `/proc/driver/nvidia/params`: `DynamicPowerManagement: 3`.

`hardware.nvidia.powerManagement.finegrained = false` does **not** disable
driver-side RTD3 — it omits the `NVreg_DynamicPowerManagement=0x02` param, and
595.71.05 then defaults to `3` ("driver decides"), which on this board resolves
to fine-grained enabled. What `finegrained = true` actually adds is the udev
rule setting `power/control=auto`; `grep -rn 'power/control' /etc/udev/rules.d/`
returns nothing, so nothing ever flips it.

Note also that flipping it would change nothing *right now*: `runtime_usage: 2`
decomposes as one reference from `pm_runtime_forbid()` plus one from the active
modeset client — the second survives `control=auto`, so a lit display pins the
device in D0 regardless. **The finegrained question is orthogonal to the user's
question and only matters when the cable is out.** [decomposition inferred from
the kernel's runtime-PM refcount semantics; not directly instrumented]

## 5. There is a MUX, but only for the internal panel, and it points the wrong way

`card1-eDP-2` exists on the NVIDIA card and reads `disconnected` — that is the
Advanced Optimus leg for the built-in display, currently routed to the iGPU by
the SBIOS "Hybrid" setting. Switching the BIOS to discrete/dGPU-only would move
`eDP-1` onto NVIDIA too, i.e. strictly more dGPU power, never less. There is no
MUX on HDMI-A-1.

## Measurements

**Idle time series, 2 s interval, 12 samples, machine in normal use:**

| pstate | gclk MHz | mclk MHz | W | °C | GPU % | mem % |
|---|---|---|---|---|---|---|
| P4 | 690 | 9001 | 10.57 | 61 | 9 | 1 |
| P5 | 345 | 810 | 9.54 | 60 | 7 | 1 |
| P8 | 360 | 405 | 7.64 | 60 | 0 | 0 |
| P8 | 270 | 405 | 8.78 | 60 | 7 | 1 |
| P5 | 382 | 405 | 9.99 | 60 | 0 | 0 |
| P8 | 765 | 810 | 10.91 | 60 | 29 | 10 |
| P5 | 555 | 405 | 9.90 | 61 | 0 | 0 |
| P8 | 922 | 9001 | 11.09 | 60 | 30 | 8 |
| P5 | 960 | 405 | 10.23 | 61 | 22 | 4 |
| P5 | 427 | 810 | 11.12 | 60 | 24 | 3 |
| P4 | 765 | 810 | 9.91 | 61 | 4 | 2 |
| P8 | 562 | 810 | 8.74 | 60 | 13 | 4 |

`nvidia-smi dmon -c 15` over the same window: SM min 1 %, max 28 %, **mean
13.2 %**; power 9–11 W. Ten consecutive 1 s `power.draw` reads averaged
**9.66 W**.

The ~14 % utilisation in the original report is **real, not a sampling
artifact** — it is sway compositing 1920×1080@60. It reproduces in a continuous
`dmon` stream that does not re-open the device per sample.

**P-state is not stuck.** It oscillates P4↔P8 with load; graphics clock ranges
270–960 MHz against a 3090 MHz ceiling; memory clock drops to its 405 MHz floor
between frames. Nothing is pinned high. **There is no lower P-state to reach** —
P8 at 405 MHz mclk is the floor, and it is already hitting it, at 7.6 W.

**Split of the 9.7 W** (from the correlation above — 1 % SM → 9 W, 28 % SM →
9–11 W):

| component | W | avoidable? |
|---|---|---|
| D0 floor: GSP firmware, PCIe link, display engine, VRAM refresh | ~7.6 | only by powering the GPU off |
| sway compositing at 13 % SM | ~1–2 | in principle (see options) |
| **total** | **~9.7** | |

For scale: package PPT reads 30–31 W (`hwmon9/power1_input`), CPU 71–73 °C. The
dGPU is roughly **a quarter of system power** and it is dumping it into the same
chassis the CPU is already thermally struggling in.

PCIe is already downtrained to the minimum: `2.5 GT/s PCIe` × 8 (Gen1 of a Gen4
link). Nothing to win there.

## Options, with costs

| option | Δ W | risk | testable without disruption |
|---|---|---|---|
| **Unplug HDMI, use the internal panel** | **−9.7** (needs §4 fixed first, else −0) | none | yes |
| Fix `power/control=auto` so the GPU can suspend *when unplugged* | 0 while plugged, −9.7 when unplugged | the 2026-07-26 wedge claim; see below | needs rebuild |
| Move monitor to another port | **0 — impossible**, §1 | — | settled by connector enumeration |
| `WLR_RENDER_DRM_DEVICE=/dev/dri/renderD129` (amdgpu renders, NVIDIA scans out) | −1 to −2 at best, plausibly net 0 | wlroots still blits into the NVIDIA scanout buffer per frame *and* adds ~500 MB/s of PCIe traffic; cross-vendor modifier negotiation can black-screen the session | no — needs a session restart |
| `WLR_DRM_DEVICES` pinned to amdgpu | HDMI goes **dark** (§1). Also already documented as a boot-breaking race in `sway.nix` | high | no |
| `nvidia-drm.fbdev=0` | ~0 | frees a small console FB; does not change scanout | needs rebuild |
| `nvidia-smi -pl 5` (min power limit) | 0 at idle | caps the ceiling not the floor; cripples games | reversible, but pointless |
| Lower refresh / resolution | ~0.3 at best | already at the panel's lowest useful mode (1080p60 of a 180 Hz monitor) | yes, via `swaymsg output` |
| `dynamicBoost.enable` | +W, not − | raises the ceiling | — |

**The honest answer: with the cable in, ~7.6 W is a hard floor and nothing in
software reaches below it.** The dGPU is the display controller; it cannot be
powered off while it is displaying. The user's intuition ("it should only be on
for games/video") is correct as a *design* expectation and simply does not hold
on a chassis where the OEM wired every external port to the discrete GPU. The
only lever with a real number on it is not plugging the monitor in.

### Re-examining the D3cold claim

The 2026-07-26 note attributes the finegrained ban to the boot-time SBIOS
errors, which are still present on 595.71.05 / 6.12.85:
```
NVRM: ... PlatformRequestHandler failed to get target temp from SBIOS
NVRM: ... PlatformRequestHandler failed to get platform power mode from SBIOS
```
Those are the **PlatformRequestHandler** path — Dynamic Boost and thermal
arbitration. RTD3 is a different subsystem, and the driver reports it as
`Enabled (fine-grained)` with `Video Memory Off: Supported` on this exact boot.
The causal link asserted in the old note is **not established by this evidence**.
It is also not disproved — testing it costs a rebuild plus a session that may not
come up, which was out of scope here. Flagging it as unverified, not wrong.

## Not the cause (retracted)

- **"It's just lit because something holds `/dev/nvidia0` open."** No. `sway`
  holds the node *because* it is the DRM master driving an active CRTC. Closing
  the fd is not a thing that can happen without the monitor going dark.
- **"14 % util is a sampling artifact from `nvidia-smi`."** No — reproduces in a
  continuous `dmon` stream, mean 13.2 % across 15 samples, and `pmon` attributes
  every bit of it to `sway`.
- **"P5 means it's stuck in a mid power state."** No. It cycles P4–P8 and hits
  the 405 MHz memory floor regularly. There is no lower state while a display is
  attached.
- **"There might be a MUX or another port."** There is a MUX, on `eDP-2`, for the
  internal panel only, and it currently points *away* from NVIDIA. §5.
- **`hardware.nvidia.powerManagement.finegrained = false` is not the reason the
  GPU is awake right now.** It is the reason it never sleeps when *unplugged*.
  Two separate problems, §4.

## Watch list

1. **`power/control=on` / `runtime_enabled: forbidden`** — the dGPU has spent
   1.25 s suspended in 2.9 h of uptime and 0 samples across five boots. Until
   this is addressed, no amount of unplugging saves anything. Blocked on
   re-testing the 2026-07-26 wedge claim, which needs a rebuild and a session
   that may not come up. `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status`.
2. **`sensor-sampler` on the running system still caches hwmon lookups outside
   the loop** — `/nix/store/cl1rxm5822vd4k1hrb9pwcfkb957ba6j-…/sensor-sampler-start`
   resolves `k10`/`amd`/`bat` before `while true`. The per-sample fix landed in
   `33e3f648` at 2026-08-31 23:37, thirteen minutes *after* the running system
   was activated at 21:27. So every `igpu=0C ppt=0W` in this boot's journal is
   the stale race, **not** a real reading — live `hwmon9` reads 70 °C / 31.2 W.
   Resolves itself on the next rebuild; noted so nobody reads those zeros.
3. **If the monitor is ever moved to a USB-C port** — it will land on `DP-1` or
   `DP-2`, still card1, still NVIDIA, still ~9.7 W. `ucsi_acpi` is blacklisted
   (`graphics.nix`) so `/sys/class/typec/` does not exist and DP-alt-mode state
   is invisible; the DRM connector list is the authority and it says card1.
