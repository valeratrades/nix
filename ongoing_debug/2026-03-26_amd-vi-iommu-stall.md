# AMD-Vi IOMMU Completion-Wait Timeout — 2026-03-26

## Incident
After opening VSCode, system became partially unresponsive:
- nvim could not open files
- sway commands stopped working
- Required a full reboot to recover

## Root Cause (from journalctl -b -1)
```
Mar 26 15:42:57 v-laptop kernel: AMD-Vi: Completion-Wait loop timed out
Mar 26 15:44:36 v-laptop kernel: AMD-Vi: Completion-Wait loop timed out
```

The AMD IOMMU (I/O Memory Management Unit) stalled waiting for a DMA operation to complete. When IOMMU stalls, any process doing I/O — file reads, device communication, compositor commands — hangs or fails silently. This explains both nvim and sway breaking simultaneously.

## What it was NOT
- **Not OOM**: earlyoom never triggered, session peaked at 5.4GB with 62GB available
- **Not filesystem corruption**: no ext4 errors in logs
- **Not MCE (hardware fault detected by CPU)**: no machine check exceptions logged
- **Not GPU crash**: the DMCUB errors appear on every boot and are unrelated

## VSCode's role
VSCode (Electron/Chromium) was running with 2.2GB peak memory. Two `code` processes crashed with SIGTRAP at shutdown (pids 256196, 263347). Electron apps are heavy on GPU compositing and DMA — the IOMMU timeout appeared ~9 minutes after boot, consistent with VSCode startup triggering heavy GPU/DMA activity.

## Mitigation applied
Added `amd_iommu=fullflush` to kernel params in `os/nixos/configuration.nix`. This forces the IOMMU to do a full TLB flush on every operation instead of batched/lazy flushes. It's slower but eliminates the completion-wait race condition.

## NB — CRITICAL HISTORY

This exact class of failure (IOMMU/DMA stalls causing cascading system corruption) is believed to have killed the previous laptop. The old machine accumulated damage over time from repeated incidents like this, eventually becoming unrecoverable.

**Utmost attention is needed to ensure this has not left lingering effects on the current machine.** Specifically:

1. **Filesystem integrity**: Run `sudo e2fsck -n /dev/nvme1n1p3` and `sudo e2fsck -n /dev/nvme0n1p3` (read-only check) to verify no silent corruption occurred during the stall
2. **NVMe health**: Run `sudo smartctl -a /dev/nvme0n1` and `sudo smartctl -a /dev/nvme1n1` — check for media errors, unsafe shutdowns counter, and critical warnings
3. **Monitor after fix**: After applying `amd_iommu=fullflush`, watch `journalctl -kf | grep AMD-Vi` during normal use. If completion-wait timeouts still appear, the IOMMU hardware itself may be degraded
4. **BIOS/firmware**: Check for BIOS updates for the Lenovo Legion — AMD has issued AGESA updates that fix IOMMU race conditions
5. **Watch for subtle corruption**: If any config files, git repos, or databases show unexplained data after this incident, treat it as potentially caused by incomplete DMA writes during the stall
