{
  lib,
  ...
}:
{
  # fuck mkOutOfStoreSymlink and home-manager. Just link everything except for where apps like to write artifacts to the config dir.
  home.activation = {
    nvim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/nvim" ] || ln -sf "$NIXOS_CONFIG/home/config/nvim" "$XDG_CONFIG_HOME/nvim"
    '';
    eww = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/eww" ] || ln -sf "$NIXOS_CONFIG/home/config/eww" "$XDG_CONFIG_HOME/eww"
    '';
    zathura = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/zathura" ] || ln -sf "$NIXOS_CONFIG/home/config/zathura" "$XDG_CONFIG_HOME/zathura"
    '';
    sway = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/sway" ] || ln -sf "$NIXOS_CONFIG/home/config/sway" "$XDG_CONFIG_HOME/sway"
    '';
    alacritty = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/alacritty" ] || ln -sf "$NIXOS_CONFIG/home/config/alacritty" "$XDG_CONFIG_HOME/alacritty"
    '';
    keyd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/keyd" ] || ln -sf "$NIXOS_CONFIG/home/config/keyd" "$XDG_CONFIG_HOME/keyd"
    '';
    mako = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/mako" ] || ln -sf "$NIXOS_CONFIG/home/config/mako" "$XDG_CONFIG_HOME/mako"
    '';
    himalaya = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/himalaya" ] || ln -sf "$NIXOS_CONFIG/home/config/himalaya" "$XDG_CONFIG_HOME/himalaya"
    '';
    nyxt = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/nyxt" ] || ln -sf "$NIXOS_CONFIG/home/config/nyxt" "$XDG_CONFIG_HOME/nyxt"
    '';

    # ind files
    tg = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ln -sf $NIXOS_CONFIG/home/config/tg.toml $XDG_CONFIG_HOME/tg.toml
    '';
    tg_admin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ln -sf $NIXOS_CONFIG/home/config/tg_admin.toml $XDG_CONFIG_HOME/tg_admin.toml
    '';
    auto_redshift = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ln -sf $NIXOS_CONFIG/home/config/auto_redshift.toml $XDG_CONFIG_HOME/auto_redshift.toml
    '';
    todo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ln -sf $NIXOS_CONFIG/home/config/todo.toml $XDG_CONFIG_HOME/todo.toml
    '';
    discretionary_engine = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ln -sf $NIXOS_CONFIG/home/config/discretionary_engine.toml $XDG_CONFIG_HOME/discretionary_engine.toml
    '';
    btc_line = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ln -sf $NIXOS_CONFIG/home/config/btc_line.toml $XDG_CONFIG_HOME/btc_line.toml
    '';
  };
}
