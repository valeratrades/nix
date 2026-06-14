{ pkgs, lib, user, mylib, ... }:
let
	disableNvidia = user.disableNvidia or false;
in
{
	services = {
		power-profiles-daemon.enable = true;
		xserver.videoDrivers = if disableNvidia
			then [ "modesetting" "amdgpu" ]
			else [ "modesetting" "amdgpu" "nvidia" ];

		xserver = {
			enable = false;
			displayManager.startx.enable = true;
			autorun = false;

			xkb = {
				options = "grp:win_space_toggle";
				extraLayouts.semimak = {
					description = "Semimak for both keyboard standards";
					languages = [ "eng" ];
					symbolsFile = mylib.relativeToRoot "home/xkb_symbols/semimak";
				};
				layout = "semimak,ru";
				variant = (if user.kbd == "ansi" then "ansi,," else "iso,,");
			};
			autoRepeatDelay = 240;
			autoRepeatInterval = 70;
		};

		libinput = {
			enable = true;
			touchpad.tapping = true;
		};
	};

	hardware = {
		graphics = {
			enable = true;
		};

		nvidia = lib.mkIf (!disableNvidia) {
			# RTX 5060 is Blackwell (GB206) - use open kernel modules
			open = true;

			# Enable hibernate/suspend support: activates nvidia-sleep.sh hooks (saves/restores VRAM)
			# and sets NVreg_PreserveVideoMemoryAllocations=1 (exposes /proc/driver/nvidia/suspend).
			# This is NOT nvidia-powerd (that's dynamicBoost.enable below) — no JPAC errors.
			powerManagement.enable = true;
			# Required for offload mode to actually pay off: lets the dGPU drop to D3cold
			# (fully powered off) whenever no offloaded app is using it. With this false the
			# card idles at P8/~8W and most of the heat win is lost.
			powerManagement.finegrained = true;
			dynamicBoost.enable = false;

			# PRIME configuration for hybrid graphics (AMD iGPU + NVIDIA dGPU)
			prime = {
				# Offload mode: AMD iGPU drives the desktop, dGPU stays powered down until an
				# app opts in via nvidia-offload / __NV_PRIME_RENDER_OFFLOAD. Sync mode (dGPU
				# renders everything, always on) was pinning the 5060 at ~34% idle util / 87°C.
				# The AMD hangs that originally motivated sync mode were fixed at the kernel level
				# (amdgpu.sg_display=0 et al — see ongoing_debug/firefox-gpu-acceleration.md), so
				# routing output through the iGPU is safe again.
				offload.enable = true;
				offload.enableOffloadCmd = true;  # provides the `nvidia-offload` wrapper
				# Bus IDs from lspci (convert hex to decimal: 01:00.0 -> 1:0:0, 06:00.0 -> 6:0:0)
				nvidiaBusId = "PCI:1:0:0";
				amdgpuBusId = "PCI:6:0:0";
			};
		};
	};

	# Always blacklist nouveau - broken support for Blackwell (RTX 50xx) causes kernel panics
	# Also blacklist ucsi_acpi - buggy USB-C driver that spams errors on Lenovo laptops
	# When nvidia disabled, also blacklist proprietary drivers
	boot.blacklistedKernelModules = [ "nouveau" "ucsi_acpi" ] ++ lib.optionals disableNvidia [
		"nvidia"
		"nvidia_modeset"
		"nvidia_uvm"
		"nvidia_drm"
	];

	# Only set nvidia kernel params when nvidia is enabled
	boot.kernelParams = lib.mkIf (!disableNvidia) [
		"nvidia-drm.modeset=1"
		"nvidia-drm.fbdev=1"
	];
}
