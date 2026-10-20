{ pkgs, lib, user, ... }: {
  programs = {
    sway = {
      enable = true;
      wrapperFeatures.gtk = true;
			extraOptions = [ "--unsupported-gpu" ] ++ lib.optional user.debug "-d"; # silences wlroots' warning about the nvidia node being present (we render on AMD in PRIME offload mode)
      # NB: do NOT pin WLR_DRM_DEVICES to /dev/dri/by-path/pci-0000:06:00.0-card — the
      # early-boot simpledrm stub and the real amdgpu node both advertise PCI 06:00.0, so
      # that by-path symlink races between the dumb framebuffer (card0, no renderer) and
      # amdgpu (card2). When the stub wins, sway gets a render-less device and the session
      # dies on boot. wlroots' own auto-selection picks the connected-display card correctly
      # and skips the nvidia node while it's in D3 offload, so we leave the device unset.
      # NVIDIA's EGL vendor out of the whole session: glvnd device enumeration otherwise opens
      # /dev/nvidia0 for the process lifetime, pinning the dGPU out of RTD3 (D3cold). HDMI on the
      # dGPU still works: wlroots without an mgpu blit renderer scans out from the primary GPU.
      # `nvidia-offload` (graphics.nix) unsets it.
      extraSessionCommands =
        "	export __EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json;\n	export XDG_CURRENT_DESKTOP=\"sway\";\n	export GDK_BACKEND=\"wayland\";\n	export XDG_BACKEND=\"wayland\";\n	export QT_WAYLAND_FORCE_DPI=\"physical\";\n	export QT_QPA_PLATFORM=\"wayland-egl\";\n	export CLUTTER_BACKEND=\"wayland\";\n	export SDL_VIDEODRIVER=\"wayland\";\n	export BEMENU_BACKEND=\"wayland\";\n	export MOZ_ENABLE_WAYLAND=\"1\";\n	# QT (needs qt5.qtwayland in systemPackages)\n	export QT_QPA_PLATFORM=wayland-egl\n	export SDL_VIDEODRIVER=wayland\n";
    };
    sway.xwayland.enable = true;
  };

  # pulls fontconfig's caches (sway's `font` line) and the session's (mesa-only) EGL stack into page cache while
  # boot is still busy elsewhere, instead of cold on the login path. See ongoing_debug/2026-10-18_slow-boot.md.
  systemd.services.sway-prewarm = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = user.username; # user's HM fontconfig dirs + ~/.cache/fontconfig
      StandardOutput = "null";
    };
    script = ''
      ${pkgs.fontconfig.bin}/bin/fc-match -s Sans
      __EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json ${pkgs.mesa-demos}/bin/eglinfo -B -p surfaceless
    '';
  };
}
