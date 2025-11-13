{ lib, ... }: {
  # fuck mkOutOfStoreSymlink and home-manager. Just link everything except for where apps like to write artifacts to the config dir.
  home.activation = {
    nvim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/nvim" ] || ln -sf "$NIXOS_CONFIG/home/config/nvim" "$XDG_CONFIG_HOME/nvim"
    '';
    eww = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/eww" ] || ln -sf "$NIXOS_CONFIG/home/config/eww" "$XDG_CONFIG_HOME/eww"
    '';
    sway = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/sway" ] || ln -sf "$NIXOS_CONFIG/home/config/sway" "$XDG_CONFIG_HOME/sway"
    '';
		btc_line = lib.hm.dag.entryAfter ["writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/btc_line.toml" ] || ln -sf "$NIXOS_CONFIG/home/config/btc_line.toml" "$XDG_CONFIG_HOME/btc_line.toml"
		'';
		social_networks = lib.hm.dag.entryAfter ["writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/social_networks.toml" ] || ln -sf "$NIXOS_CONFIG/home/config/social_networks.toml" "$XDG_CONFIG_HOME/social_networks.toml"
		'';
  };
}
