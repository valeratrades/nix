{ lib, ... }: {
  # fuck mkOutOfStoreSymlink and home-manager. Just link everything except for where apps like to write artifacts to the config dir.
  home.activation = {
    #nvim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    #  [ -e "$XDG_CONFIG_HOME/nvim" ] || ln -sf "$NIXOS_CONFIG/home/config/nvim" "$XDG_CONFIG_HOME/nvim"
    #'';
    eww = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/eww" ] || ln -sf "$NIXOS_CONFIG/home/config/eww" "$XDG_CONFIG_HOME/eww"
    '';
    sway = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/sway" ] || ln -sf "$NIXOS_CONFIG/home/config/sway" "$XDG_CONFIG_HOME/sway"
    '';
    himalaya = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/himalaya" ] || ln -sf "$NIXOS_CONFIG/home/config/himalaya" "$XDG_CONFIG_HOME/himalaya"
    '';
    claude = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$HOME/.claude" ] || ln -sf "$NIXOS_CONFIG/home/config/claude" "$HOME/.claude"
    '';

    # ind files
    auto_redshift = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ln -sf $NIXOS_CONFIG/home/config/auto_redshift.toml $XDG_CONFIG_HOME/auto_redshift.toml
    '';
    discretionary_engine = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ln -sf $NIXOS_CONFIG/home/config/discretionary_engine.toml $XDG_CONFIG_HOME/discretionary_engine.toml
    '';
    btc_line = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ln -sf $NIXOS_CONFIG/home/config/btc_line.toml $XDG_CONFIG_HOME/btc_line.toml
    '';
  };
}
