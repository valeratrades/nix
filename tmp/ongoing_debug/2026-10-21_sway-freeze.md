# Desktop freezes solid, kernel alive — power button needed

Status: **cause confirmed, fix applied** (`WLR_RENDERER=gles2`, sway.nix). Effective from the first boot after it; a sway started before it still deadlocks on the next `switch`.

## Signature

Screen and input dead, so the user presses the power button. The kernel is fine: logind takes the
press and runs a **clean** shutdown, journal flushed, `Journal stopped` present. That separates this
from `2026-08-22_unlogged-hard-reset.md`, where the journal ends mid-line.

## 2026-10-21 08:21 incident (boot 310fef8a)

```
08:20:35  nixos-rebuild switch
08:21:42  switch-to-configuration: systemd daemon-reload
08:21:43.22 nvidia-drm-late.service starts  ← the path unit re-checks its glob after reload
08:21:43.31 kernel: nvidia-drm loaded, "Cannot find any crtc or sizes" (no HDMI attached)
08:21:46.57 last eww redraw  ← eww had redrawn every 1-3s all session
08:22:00  switch finishes
08:22:31  ac=0 (charger + USB tether pulled, probably by the user, after the freeze)
08:22:50  "Power key pressed short", clean poweroff, 7s
```

Ruled out by sensor-sampler + journal: heat (62C), load (~3-6), OOM, any amdgpu/NVRM error, D-state
deadlock (sway's scope stopped in <300ms at shutdown; nvidia-persistenced stopped cleanly).

The marker is eww going silent. 60s+ eww gaps also show up while idle (nights, screen off), but
during active use the longest gap in boot -2 was 10s.

## Prime suspect: nvidia_drm hot-loaded into a running sway

`nvidia-drm-late.path` (graphics.nix) is meant to fire right after sway starts at boot. It **never
does**: no nvidia-drm load at boot in boots 0, -1, -2. It fires instead on the next system
daemon-reload, i.e. the first `nixos-rebuild switch` of the boot, into a live session. wlroots then
hotplugs card0.

Against it: boot -3 did the same live load (2026-10-20 16:53:52) and sway survived. What changed in
between: dd38860a (16:57) hid NVIDIA EGL from the session (`__EGL_VENDOR_LIBRARY_FILENAMES` = mesa
only) and enabled nvidia-persistenced. Boot -3 also probably had HDMI attached (an eww burst at
16:53:53 suggests a new output), while 10-21 had no crtc.

## Instrumentation (2026-10-21)

- sway's stderr goes to the journal: `journalctl -b -1 -t sway` (was `~/.sway.log`, truncated each boot).
- sensor-sampler: `sway=ok|STALL|none` on every line. After two failed IPC probes in a row
  (~7-10s), it dumps once: per-thread kernel stacks and wchan, an `eu-stack` userspace backtrace
  (`sway-stall` prefix), and `sysrq w`, which puts blocked tasks into the kernel log.
  Query: `journalctl -b -1 -u sensor-sampler -g 'sway'`, `journalctl -b -1 -k -g 'blocked'`.
  If sway answers IPC while the screen is frozen, `sway=ok` up to the power press points below
  sway: KMS/display or GPU.

## Next incident

1. `journalctl -b -1 -t nvidia-drm-late -u nvidia-drm-late` — did it fire live again?
2. `sway-stall` backtrace: which library is sway stuck in (libEGL_nvidia / wlr drm / amdgpu ioctl).
3. If it's the hotplug: fix the path unit's boot-time trigger, so the load happens before any
   client exists and never mid-session.

## Confirmed 2026-10-21 08:31 — sway deadlocks against its own Xwayland

A `nixos-rebuild switch` restarted `nvidia-drm-late.path` (even though it had been stopped by hand),
nvidia_drm loaded, and sway hung within a second. sway's main thread (`eu-stack`, boot 3860abdc):

```
handle_udev_event → handle_add_drm_card → wlr_drm_backend_create → init_drm_renderer
→ renderer_autocreate → wlr_vk_renderer_create_with_drm_fd → vkEnumerateInstanceExtensionProperties
→ loader_icd_scan → (NVIDIA Vulkan ICD) vk_icdNegotiateLoaderICDInterfaceVersion
→ XOpenDisplay → xcb_connect → poll()   ← forever
```

The NVIDIA Vulkan ICD opens `$DISPLAY` while it initializes. sway's own environment has DISPLAY
pointing at Xwayland, and sway serves Xwayland, so sway waits on itself. GLES was tried first and
failed, because NVIDIA EGL is hidden from the session (dd38860a). That is why wlroots fell through
to Vulkan. (Boot -3 had EGL hidden too: its 09:04:56 hotplug logs the same GLES failure.)

Trigger: any system daemon-reload while nvidia_drm is not loaded yet. It never loads at boot, so
**the first `nixos-rebuild switch` of every boot freezes the desktop.**

## Fix: `WLR_RENDERER=gles2` in sway's env

wlroots 0.19.3 `renderer_autocreate`: with WLR_RENDERER=gles2, only GLES is tried. It fails on
card0 (mesa-only EGL), so `init_mgpu_renderer` logs "falling back to scanning out from primary
GPU" and returns true. Vulkan is never entered. **Wrong: HDMI does NOT light up** — the output stays
power=false/0x0, every modeset logs "Requested backend configuration failed" (boots of 2026-10-21 14:53, 17:40).
Cross-GPU direct scanout doesn't work here; sway needs a real GLES renderer on card0 → NVIDIA EGL unhidden
for the session again (dGPU was D0/active anyway: sway holds card0 for KMS, chrome holds it too). AMD was
already on GLES under `auto` (GLES is tried first), so the desktop doesn't change.

Rejected: hiding the NVIDIA Vulkan ICD via `VK_DRIVER_FILES`. It leaks into every app and needs
another unset in `nvidia-offload`, whereas WLR_RENDERER is read only by wlroots.

`nvidia-drm-late.path` never fired at boot: it started (00:02:39.7) before user-runtime-dir@1000 mounted the
/run/user/1000 tmpfs (00:02:41.2), so its inotify watch sat on the covered dir. Fix 541ac02c: path unit
wantedBy/after/bindsTo user-runtime-dir@uid. Unverified until a fresh boot: HDMI-A-1 should be in
`swaymsg -t get_outputs` with no switch, and `journalctl -b -u nvidia-drm-late` should show a start ~at login.
Verified 2026-10-23: a live `systemctl start nvidia-drm-late` (gles2 + NVIDIA EGL) hotplugs HDMI without freezing sway.
