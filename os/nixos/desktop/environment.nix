{ pkgs, user, ... }: {
  environment.variables = {
    QT_QPA_PLATFORMTHEME = "flatpak";
    GTK_USE_PORTAL = "1";
    GDK_DEBUG = "portals";
    DEFAULT_BROWSER = "${pkgs.google-chrome}/bin/google-chrome-stable";
    WINEPREFIX = "/home/${user.username}/.wine";
  };

  #TEST: Workaround for NVIDIA/WiFi blocking hibernation - use platform hibernation mode
  systemd.services.systemd-hibernate.serviceConfig = {
    ExecStartPre = "${pkgs.coreutils}/bin/echo platform > /sys/power/disk";
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