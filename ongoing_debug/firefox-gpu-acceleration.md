# Firefox / browser GPU acceleration on the AMD iGPU — what's safe, what isn't

Status: **stable as of 2026-05-30**. No amdgpu hangs, GPU resets, or AMD-Vi
Completion-Wait timeouts in the journal for the last 30 days with the config below.

## The original problem (Dec 2025)

The AMD iGPU (Raphael, `06:00.0`) would **hang**, taking down the whole graphical
session — terminals/GUIs stopped responding, required a hard reboot. Opening
GPU-heavy apps (VSCode/Electron, and browser canvas/WebGL) was the trigger.

This is the same DMA/IOMMU-stall failure class documented in
`2026-03-26_amd-vi-iommu-stall.md`. Believed to have killed the previous laptop
over time, so we are **deliberately conservative** here.

## What actually fixed it — kernel level, not Firefox

The Firefox `gfx.webrender.all = false` flip in Dec 2025 was a **band-aid**. The
real fixes are kernel params in `os/nixos/configuration.nix`:

- `amdgpu.sg_display=0`   — disable scatter-gather display (the direct cause of GPU crashes)
- `amdgpu.dcdebugmask=0x10` — disable PSR (Panel Self Refresh)
- `amdgpu.noretry=1`      — no retry on page faults
- `iommu.strict=1`        — synchronous TLB invalidation (replaces deprecated amd_iommu=fullflush)

Once these landed, the Firefox GPU prefs could be turned back on without regressions.

## Re-enablement timeline (in `firefox.nix`)

| Date       | Change                                                        |
|------------|---------------------------------------------------------------|
| 2025-12-06 | `gfx.webrender.all = false` — GPU rendering fully OFF (the break) |
| 2026-01-17 | WebRender back ON; hardware video decode kept OFF             |
| 2026-04-14 | Hardware video decode + VA-API back ON                        |
| 2026-05-30 | DMABUF + native compositor + isolated GPU process (this doc)  |

## Current Firefox GPU prefs and WHY each is safe

| pref | value | rationale |
|------|-------|-----------|
| `gfx.webrender.all` | true | GPU compositor. Stable since kernel fixes. |
| `media.hardware-video-decoding.enabled` | true | VA-API decode via radeonsi. |
| `media.ffmpeg.vaapi.enabled` | true | Wayland VA-API path. |
| `media.hardware-video-decoding.force-enabled` | **false** | never override the driver blacklist. |
| `widget.dmabuf.force-enabled` | true | zero-copy buffer sharing; the standard, stable radeonsi Wayland path. |
| `gfx.webrender.compositor` | true | native Wayland composite, fewer GPU copies. |
| `layers.gpu-process.enabled` | true | **isolates** GPU work — a WebGL crash recovers instead of killing the page or session. |
| `layers.gpu-process.max_restarts` | 5 | auto-respawn before software fallback. |

## The Excalidraw case (why these prefs, specifically)

Excalidraw is **WebGL/canvas-heavy**, not video. It was crashing. Two failure
directions, and we steer between them:

- **Too little accel** → software canvas, large boards stutter / OOM the content
  process → looks like a crash.
- **Too much accel** → force-enabling GPU canvas / WebGL *overrides the driver
  blacklist* and re-enters the exact amdgpu path that hung the GPU originally.

The fix is the middle ground: give it real GPU compositing (DMABUF + native
compositor) **and** put GPU work in an isolated, auto-restarting process so a
flaky WebGL operation degrades gracefully — without ever force-overriding the
blacklist.

## ⚠️ DO NOT add these — they re-introduce the regression

These force-override the driver's GPU blacklist, which is precisely what risks
re-triggering the amdgpu hang. Leave them at their (blacklist-respecting) defaults:

- `gfx.canvas.accelerated.force-enabled`
- `webgl.force-enabled`
- `gfx.webrender.software` set to false-by-force / any `*.force-enabled` for GPU paths
- `media.hardware-video-decoding.force-enabled = true`

## If a GPU hang recurs

1. Check `journalctl -kf | grep -iE 'amdgpu|AMD-Vi'` for the crash signature.
2. First suspect: a newly-added `*.force-enabled` pref here — revert it.
3. If it persists without a Firefox change, it's the kernel/IOMMU class — see
   `2026-03-26_amd-vi-iommu-stall.md` (next escalation is `iommu=soft` / `amd_iommu=off`).
