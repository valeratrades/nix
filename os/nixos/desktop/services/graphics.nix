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

			# Disable power management - nvidia-powerd spams JPAC errors and causes system freezes
			powerManagement.enable = false;
			#dbg: investigating hard lockups (2025-12-09) - disable fine-grained power management to prevent GPU sleep/wake cycles
			powerManagement.finegrained = false; #TEST: supposed to prevent GPU wake-up
			dynamicBoost.enable = false;

			# PRIME configuration for hybrid graphics (AMD iGPU + NVIDIA dGPU)
			prime = {
				# Use offload mode - AMD iGPU renders by default, NVIDIA on-demand
				offload = {
					enable = true;
					enableOffloadCmd = true;  # provides `nvidia-offload` command
				};
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
