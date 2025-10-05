{ self, config, lib, pkgs, user, inputs, ... }: {
  # Desktop-specific services and programs that were moved from configuration.nix

  programs = {
    sway = {
      enable = true;
      wrapperFeatures.gtk = true;
      extraSessionCommands =
        "	export XDG_CURRENT_DESKTOP=\"sway\";\n	export GDK_BACKEND=\"wayland\";\n	export XDG_BACKEND=\"wayland\";\n	export QT_WAYLAND_FORCE_DPI=\"physical\";\n	export QT_QPA_PLATFORM=\"wayland-egl\";\n	export CLUTTER_BACKEND=\"wayland\";\n	export SDL_VIDEODRIVER=\"wayland\";\n	export BEMENU_BACKEND=\"wayland\";\n	export MOZ_ENABLE_WAYLAND=\"1\";\n	# QT (needs qt5.qtwayland in systemPackages)\n	export QT_QPA_PLATFORM=wayland-egl\n	export SDL_VIDEODRIVER=wayland\n";
    };
    sway.xwayland.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
      xdg-desktop-portal-shana
      lxqt.xdg-desktop-portal-lxqt
    ];
    wlr.activate = true;
  };

  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "flatpak";
    GTK_USE_PORTAL = "1";
    GDK_DEBUG = "portals";
    DEFAULT_BROWSER = "${pkgs.google-chrome}/bin/google-chrome-stable";
    WINEPREFIX = "${config.home.homeDirectory}/.wine";
    PKG_CONFIG_PATH = "${pkgs.alsa-lib.dev}/lib/pkgconfig:${pkgs.wayland-scanner.bin}/bin";
  };

  home.activation = {
    # Desktop-specific activation scripts
    copyAlacrittyConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Copy the alacritty config and set permissions
      if [ -f "${config.home.homeDirectory}/.config/alacritty/alacritty.toml.hm" ]; then
        cp "${config.home.homeDirectory}/.config/alacritty/alacritty.toml.hm" "${config.home.homeDirectory}/.config/alacritty/alacritty.toml"
        chmod 0666 "${config.home.homeDirectory}/.config/alacritty/alacritty.toml"
      fi
    '';
  };
}