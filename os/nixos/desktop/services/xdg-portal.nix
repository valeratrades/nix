{ pkgs, ... }: {
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
      #xdg-desktop-portal-gnome #dbg: may be bringning in `webkitgtk`
      xdg-desktop-portal-shana
      lxqt.xdg-desktop-portal-lxqt
      xdg-desktop-portal-termfilechooser
    ];
    wlr = {
      enable = true;
      settings.screencast = {
        chooser_type = "simple"; # default chain skips slurp whenever the client also accepts windows (xdpw >=0.8)
        chooser_cmd = "${pkgs.slurp}/bin/slurp -f 'Monitor: %o' -or";
      };
    };
  };
}
