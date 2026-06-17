{ ... }: {
  programs = {
    sway = {
      enable = true;
      wrapperFeatures.gtk = true;
			extraOptions = [ "--unsupported-gpu" ]; # silences wlroots' warning about the nvidia node being present (we render on AMD in PRIME offload mode)
      # NB: do NOT pin WLR_DRM_DEVICES to /dev/dri/by-path/pci-0000:06:00.0-card — the
      # early-boot simpledrm stub and the real amdgpu node both advertise PCI 06:00.0, so
      # that by-path symlink races between the dumb framebuffer (card0, no renderer) and
      # amdgpu (card2). When the stub wins, sway gets a render-less device and the session
      # dies on boot. wlroots' own auto-selection picks the connected-display card correctly
      # and skips the nvidia node while it's in D3 offload, so we leave the device unset.
      extraSessionCommands =
        "	export XDG_CURRENT_DESKTOP=\"sway\";\n	export GDK_BACKEND=\"wayland\";\n	export XDG_BACKEND=\"wayland\";\n	export QT_WAYLAND_FORCE_DPI=\"physical\";\n	export QT_QPA_PLATFORM=\"wayland-egl\";\n	export CLUTTER_BACKEND=\"wayland\";\n	export SDL_VIDEODRIVER=\"wayland\";\n	export BEMENU_BACKEND=\"wayland\";\n	export MOZ_ENABLE_WAYLAND=\"1\";\n	# QT (needs qt5.qtwayland in systemPackages)\n	export QT_QPA_PLATFORM=wayland-egl\n	export SDL_VIDEODRIVER=wayland\n";
    };
    sway.xwayland.enable = true;
  };
}
