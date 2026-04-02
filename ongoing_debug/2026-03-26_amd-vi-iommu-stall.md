# AMD-Vi IOMMU Completion-Wait Timeout — recurring

## Incidents

### 2026-03-31 (today)
Opened VSCode → system froze (new terminals/GUIs wouldn't open). Required hard reboot.
Boot -2 (12:49-14:23): ~1.5hr session. VSCode `code` process crashed with SIGTRAP (pid 964586). No IOMMU timeout in logs — likely didn't flush before hard reset.
Boot -1 (14:23-14:40): 17min reboot, no IOMMU timeout logged.
Boot 0 (14:49-now): `AMD-Vi: Completion-Wait loop timed out` at 14:49:25, **21 seconds after boot**. Single timeout, system appears functional after.

### 2026-03-26 (original)
After opening VSCode, system became partially unresponsive:
- nvim could not open files
- sway commands stopped working
- Required a full reboot to recover

```
Mar 26 15:42:57 v-laptop kernel: AMD-Vi: Completion-Wait loop timed out
Mar 26 15:44:36 v-laptop kernel: AMD-Vi: Completion-Wait loop timed out
```

## Root Cause
The AMD IOMMU stalls waiting for a DMA operation to complete. When IOMMU stalls, any process doing I/O — file reads, device communication, compositor commands — hangs or fails silently.

VSCode (Electron/Chromium) is heavy on GPU compositing and DMA. Both incidents were triggered by opening VSCode.

## What it was NOT
- **Not OOM**: earlyoom never triggered, session peaked at 5.4GB with 62GB available
- **Not filesystem corruption**: no ext4 errors in logs
- **Not MCE (hardware fault detected by CPU)**: no machine check exceptions logged
- **Not GPU crash**: the DMCUB errors appear on every boot and are unrelated

## Mitigation history

### v1: `amd_iommu=fullflush` (2026-03-26) — FAILED
Kernel 6.12.77 logs: `AMD-Vi: amd_iommu=fullflush deprecated; use iommu.strict=1 instead`
The flag is **ignored** on this kernel version. The 2026-03-31 incident proves it did not prevent the timeout.

### v2: `iommu.strict=1` (2026-03-31) — APPLIED, NEEDS TESTING
Replaced `amd_iommu=fullflush` with `iommu.strict=1` in `os/nixos/configuration.nix`.
This is the current kernel-supported equivalent: forces synchronous TLB invalidation on every unmap.

### v3 (if v2 fails): `iommu=soft` or `amd_iommu=off`
Nuclear option — disables hardware IOMMU entirely, falling back to software bounce buffers.
Loses VFIO/passthrough capability and some security isolation, but eliminates the stall entirely.
**Only use if `iommu.strict=1` still produces Completion-Wait timeouts.**

## Healthcheck (2026-03-31)

### NVMe drives — OK
- **NVMe0 (UMIS 1TB)**: PASSED. 0 media errors, 0 error log entries, 5% used, 100% spare
- **NVMe1 (Kingston 1TB)**: PASSED. 0 media errors, 0 error log entries, 2% used, 100% spare
- Both drives: 175 unsafe shutdowns (accumulated from hard reboots — not ideal but no damage detected)

### Memory — OK
51GB available of 62GB. No OOM. No memory errors.

### Filesystem — NOT YET CHECKED
TODO: Run `sudo e2fsck -n /dev/nvme0n1p3` and `sudo e2fsck -n /dev/nvme1n1p3` (read-only check) from a live USB or single-user mode.

## Hardware info
- **Laptop**: Lenovo Legion 83LV
- **BIOS**: RLCN29WW
- **Kernel**: 6.12.77
- **IOMMU**: AMD-Vi, EFR 0x246577efa2254afa

## NB — CRITICAL HISTORY

This exact class of failure (IOMMU/DMA stalls causing cascading system corruption) is believed to have killed the previous laptop. The old machine accumulated damage over time from repeated incidents like this, eventually becoming unrecoverable.

## TODO
1. **Reboot** with `iommu.strict=1` and test by opening VSCode
2. **Monitor**: `journalctl -kf | grep AMD-Vi` during VSCode usage
3. **BIOS update**: Check Lenovo support for RLCN29WW → newer BIOS for Legion 83LV (AMD AGESA updates fix IOMMU race conditions)
4. **Filesystem check**: `sudo e2fsck -n` on both root partitions from live USB
5. **If v2 fails**: Apply `iommu=soft` or `amd_iommu=off` and test
6. **Add smartmontools and nvme-cli** to system packages for future healthchecks
