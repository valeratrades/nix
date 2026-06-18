{ self, config, lib, pkgs, user, inputs, ... }:
let
  # Close hidden tabs matching a kill-list (bitunix.com/markets — a live-data
  # listing page that pegs several cores in the background and reopens trivially).
  # Source of truth is the committed script; writePython3Bin lints it at build.
  chromeTabReaper = pkgs.writers.writePython3Bin "chrome-tab-reaper" { }
    (builtins.readFile "${self}/home/scripts/chrome_tab_reaper.py");
in
{
  # Desktop-specific home-manager services and programs

  # EasyEffects service for audio limiting/protection
  # NOTE: Disabled because limiter plugin is not working correctly yet.
  # Audio routing is broken - limiter doesn't apply any gain reduction.
  # Use manually via: ~/nix/home/scripts/easyeffects-spl-limiter
  # services.easyeffects = {
  #   enable = true;
  #   preset = "headphone-safety-limiter";
  # };

  #XXX: don't seem to be picked up (eg try to echo `TERMCMD` one)
  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "xdgdesktopportal";
    GTK_USE_PORTAL = "1";
    GDK_DEBUG = "portals";
    DEFAULT_BROWSER = "${pkgs.google-chrome}/bin/google-chrome-stable";
    WINEPREFIX = "${config.home.homeDirectory}/.wine";
    PKG_CONFIG_PATH = "${pkgs.alsa-lib.dev}/lib/pkgconfig:${pkgs.wayland-scanner.bin}/bin";
    # Terminal emulator for xdg-desktop-portal-termfilechooser
    TERMCMD = "alacritty -t termfilechooser -e";
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

  systemd.user.services.chrome-tab-reaper = {
    Unit.Description = "Close hidden Chrome tabs matching the CPU-hog kill-list";
    Service = {
      Type = "oneshot";
      ExecStart = "${chromeTabReaper}/bin/chrome-tab-reaper";
    };
  };

  systemd.user.timers.chrome-tab-reaper = {
    Unit.Description = "Periodically reap hidden CPU-hog Chrome tabs";
    Timer = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
