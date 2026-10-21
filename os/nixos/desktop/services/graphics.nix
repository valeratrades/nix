{ config, pkgs, lib, user, mylib, ... }:
let
	disableNvidia = user.disableNvidia or false;
in
{
	services = {
		# power-profiles-daemon is owned (and disabled) by services/thermal.nix — it races our own
		# thermal management for platform_profile. Nothing graphics-related consumed it.
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
			# NB: finegrained (D3cold power-gating, NVreg_DynamicPowerManagement=0x02) wedges the
			# 5060 on this chassis — the SBIOS can't report power mode/temp (see boot log:
			# "PlatformRequestHandler failed to get platform power mode from SBIOS"), so the
			# driver can't safely power-gate and the session fails to come up. Offload mode alone
			# already drops the dGPU to P8 idle; the big heat win is AMD driving the desktop, not D3cold.
			powerManagement.finegrained = false;
			dynamicBoost.enable = false;
			# A client that never closes: the driver's last-close adapter teardown deadlocks against ACPI
			# power-source events. See ongoing_debug/2026-10-20_dgpu-runtime-off.md.
			nvidiaPersistenced = true; #TEST: idle dGPU reaches runtime_status=suspended (D3cold) with no deadlock. See ongoing_debug/2026-10-20_dgpu-runtime-off.md

			# PRIME configuration for hybrid graphics (AMD iGPU + NVIDIA dGPU)
			prime = {
				# Offload mode: AMD iGPU drives the desktop, dGPU stays powered down until an
				# app opts in via nvidia-offload / __NV_PRIME_RENDER_OFFLOAD. Sync mode (dGPU
				# renders everything, always on) was pinning the 5060 at ~34% idle util / 87°C.
				# The AMD hangs that originally motivated sync mode were fixed at the kernel level
				# (amdgpu.sg_display=0 et al — see ongoing_debug/firefox-gpu-acceleration.md), so
				# routing output through the iGPU is safe again.
				offload.enable = true;
				# Bus IDs from lspci (convert hex to decimal: 01:00.0 -> 1:0:0, 06:00.0 -> 6:0:0)
				nvidiaBusId = "PCI:1:0:0";
				amdgpuBusId = "PCI:6:0:0";
			};
		};
	};

	# Always blacklist nouveau - broken support for Blackwell (RTX 50xx) causes kernel panics
	# Also blacklist ucsi_acpi - buggy USB-C driver that spams errors on Lenovo laptops
	# When nvidia disabled, also blacklist proprietary drivers
	boot.blacklistedKernelModules = [ "nouveau" "ucsi_acpi" "nvidia_drm" ] ++ lib.optionals disableNvidia [
		"nvidia"
		"nvidia_modeset"
		"nvidia_uvm"
	];

	# nvidia_drm (blacklisted above against udev's PCI autoload) comes up only once sway has picked
	# its GPUs, so sway starts on AMD alone and wlroots' DRM hotplug monitor adds card1 (HDMI) when
	# it registers. See ongoing_debug/2026-10-18_slow-boot.md.
	systemd.paths.nvidia-drm-late = lib.mkIf (!disableNvidia) {
		wantedBy = [ "multi-user.target" ];
		pathConfig.PathExistsGlob = "/run/user/${toString config.users.users.${user.username}.uid}/wayland-*"; # sway binds its socket after wlr_backend_autocreate; a glob in a dir component is never inotify-watched
	};
	systemd.services.nvidia-drm-late = lib.mkIf (!disableNvidia) {
		serviceConfig = {
			Type = "oneshot";
			RemainAfterExit = true; # else the still-existing socket re-triggers it
			ExecStart = "${pkgs.kmod}/bin/modprobe nvidia_drm"; # explicit name, so the blacklist doesn't apply
		};
	};

	environment.systemPackages = lib.optional (!disableNvidia) (pkgs.writeShellScriptBin "nvidia-offload" ''
		export __NV_PRIME_RENDER_OFFLOAD=1
		export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
		export __GLX_VENDOR_LIBRARY_NAME=nvidia
		export __VK_LAYER_NV_optimus=NVIDIA_only
		exec "$@"
	'');

	# Only set nvidia kernel params when nvidia is enabled
	boot.kernelParams = lib.mkIf (!disableNvidia) [
		"nvidia-drm.modeset=1"
		"nvidia-drm.fbdev=1"
	];
}
