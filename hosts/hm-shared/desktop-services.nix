{ self, config, lib, pkgs, user, inputs, ... }: {
  # Desktop-specific home-manager services and programs

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