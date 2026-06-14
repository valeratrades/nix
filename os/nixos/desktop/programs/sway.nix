{ ... }: {
  programs = {
    sway = {
      enable = true;
      wrapperFeatures.gtk = true;
			extraOptions = [ "--unsupported-gpu" ]; # silences wlroots' warning about the nvidia node being present (we render on AMD in PRIME offload mode)
      # Pin the compositor to the AMD iGPU (PCI 06:00.0) so wlroots doesn't grab the
      # nvidia node and keep the dGPU hot. by-path symlink is stable across boots,
      # unlike cardN numbering. The dGPU now only spins up for offloaded apps.
      extraSessionCommands =
        "	export WLR_DRM_DEVICES=\"/dev/dri/by-path/pci-0000:06:00.0-card\";\n	export XDG_CURRENT_DESKTOP=\"sway\";\n	export GDK_BACKEND=\"wayland\";\n	export XDG_BACKEND=\"wayland\";\n	export QT_WAYLAND_FORCE_DPI=\"physical\";\n	export QT_QPA_PLATFORM=\"wayland-egl\";\n	export CLUTTER_BACKEND=\"wayland\";\n	export SDL_VIDEODRIVER=\"wayland\";\n	export BEMENU_BACKEND=\"wayland\";\n	export MOZ_ENABLE_WAYLAND=\"1\";\n	# QT (needs qt5.qtwayland in systemPackages)\n	export QT_QPA_PLATFORM=wayland-egl\n	export SDL_VIDEODRIVER=wayland\n";
    };
    sway.xwayland.enable = true;
  };
}
