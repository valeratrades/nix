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
			modesetting.enable = true;
			powerManagement.enable = true;
			open = true;
			prime = {
				sync.enable = true;
				amdgpuBusId = "PCI:5:0:0";   # from 05:00.0
				nvidiaBusId = "PCI:1:0:0";   # from 01:00.0
			};
		};
	};
}
