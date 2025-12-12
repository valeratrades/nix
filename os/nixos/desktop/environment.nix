{ pkgs, user, ... }: {
  environment.variables = {
    QT_QPA_PLATFORMTHEME = "xdgdesktopportal";
    GTK_USE_PORTAL = "1";
    GDK_DEBUG = "portals";
    DEFAULT_BROWSER = "${pkgs.google-chrome}/bin/google-chrome-stable";
    WINEPREFIX = "/home/${user.username}/.wine";
    # dbg: disable GPU acceleration everywhere to test if GPU is causing crashes
    LIBVA_DRIVER_NAME = "null";  # disable VA-API (video acceleration)
    VDPAU_DRIVER = "none";       # disable VDPAU
    __GL_FSAA_MODE = "0";        # disable antialiasing
    __GL_LOG_MAX_ANISO = "0";    # disable anisotropic filtering
  };

  powerManagement = {
    powerUpCommands = "systemctl --user restart wlr-gamma\nsystemctl --user restart auto_redshift\n";
  };

  system.activationScripts.copyAlacrittyConfig = {
    text = ''
      # Copy the alacritty config and set permissions
      cp /home/${user.username}/.config/alacritty/alacritty.toml.hm /home/${user.username}/.config/alacritty/alacritty.toml
      chmod 0666 /home/${user.username}/.config/alacritty/alacritty.toml
    '';
    deps = [ ];
  };
}