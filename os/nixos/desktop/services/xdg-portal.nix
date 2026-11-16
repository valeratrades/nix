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
        chooser_type = "dmenu";
        chooser_cmd = "${pkgs.rofi}/bin/rofi -dmenu -p 'share output'"; # unit PATH lacks system bins
      };
    };
  };
}
