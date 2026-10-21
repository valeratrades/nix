# Turning the dGPU (RTX 5060, 01:00.0) fully off at runtime

Goal: `optimize_for battery` with the dGPU powered down (D3cold, VRAM off), no reboot.
Status: not achievable on driver 595.71.05 / kernel 7.0.3. Boot-time alternatives are rejected (we never operate on next boot).

## Facts
- RTD3 reports `Enabled (fine-grained)`, `Video Memory Off: Supported`; bridge 00:01.1 has _PR3 → D3cold is physically possible.
- sway opens /dev/nvidia0 + nvidiactl at startup via glvnd EGL device enumeration (libEGL_nvidia), for its lifetime.
  With that client, the GPU stays `active` (1353s active vs 3s suspended in one boot). So RTD3 never actually fires.
- `__EGL_VENDOR_LIBRARY_FILENAMES=.../50_mesa.json` removes sway's handle (headless sway: 5 fds → 0).
- But then the last close (thermal-guard's nvidia-smi) tears the adapter down: nv_stop_device → RmShutdownAdapter →
  nv_acpi_methods_uninit → acpi_remove_notify_handler flushes kacpi_notify while holding the RM lock, and the queued
  rm_power_source_change_event waits on that lock → deadlock, 50+ kworkers + every nvidia user in D state. Reboot only.
- Unload/PCI-remove at runtime: blocked by the same sway handle; graphics.nix notes finegrained wedging the card on this chassis.

- Stake: held by sway, the dGPU idles at P8, 3.74 W, 1 MiB VRAM.

## Failed (mesa-only EGL reverted 2026-10-21): dGPU stayed active/D0, HDMI on the dGPU never came up (see 2026-10-21_sway-freeze.md)
nvidia-persistenced (no last-close teardown → no deadlock) + mesa-only EGL session, so the driver's own RTD3 drops the
dGPU whenever idle, in-session, no reboots. Done when, after a fresh boot:
- `/sys/bus/pci/devices/0000:01:00.0/power/runtime_status` = suspended while idle (or does persistence keep it active?)
- `/proc/[0-9]*/fd` holders of /dev/nvidia*: only nvidia-persistenced
- `nvidia-offload <egl app>` reports NVIDIA, and the GPU suspends again after it exits
- HDMI on the dGPU still lights up (wlroots scanning out from AMD, no mgpu blit renderer)
- no D-state kworkers across AC plug/unplug
