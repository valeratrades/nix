{ pkgs, user, mylib, ... }: {
	services = {
		power-profiles-daemon.enable = true;
		xserver.videoDrivers = [ /*"displaylink"*/ "modesetting" "amdgpu" "nvidia" ];


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

		nvidia = {
			# RTX 5060 is Blackwell (GB206) - use open kernel modules
			open = true;

			# Disable power management - nvidia-powerd spams JPAC errors and causes system freezes
			powerManagement.enable = false;
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
}
