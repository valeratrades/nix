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

## Untried
- nvidia-persistenced (avoids last-close teardown) + no sway handle: does the GPU then reach D3cold? Teardown never runs,
  so the deadlock path is avoided, but persistence may itself keep the GPU active.
