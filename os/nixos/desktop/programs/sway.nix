{ ... }: {
  programs = {
    sway = {
      enable = true;
      wrapperFeatures.gtk = true;
			extraOptions = [ "--unsupported-gpu" ]; # atm I must force nvidia graphics + dGPU to get my laptop working with a monitor. This flag is then necessary.
      extraSessionCommands =
        "	export XDG_CURRENT_DESKTOP=\"sway\";\n	export GDK_BACKEND=\"wayland\";\n	export XDG_BACKEND=\"wayland\";\n	export QT_WAYLAND_FORCE_DPI=\"physical\";\n	export QT_QPA_PLATFORM=\"wayland-egl\";\n	export CLUTTER_BACKEND=\"wayland\";\n	export SDL_VIDEODRIVER=\"wayland\";\n	export BEMENU_BACKEND=\"wayland\";\n	export MOZ_ENABLE_WAYLAND=\"1\";\n	# QT (needs qt5.qtwayland in systemPackages)\n	export QT_QPA_PLATFORM=wayland-egl\n	export SDL_VIDEODRIVER=wayland\n";
    };
    sway.xwayland.enable = true;
  };
}
