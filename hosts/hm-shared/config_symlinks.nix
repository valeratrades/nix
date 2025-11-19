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
		claude_code_global_CLAUDE_md = 
      let
        target_path = "$HOME/.claude/CLAUDE.md";
      in
      lib.hm.dag.entryAfter ["writeBoundary" ] ''
      [ -e "${target_path}" ] || ln -sf "$NIXOS_CONFIG/home/config/claude/CLAUDE.md" "${target_path}"
		'';
		rm_engine = 
      let
        target_path_postfix = "rm_engine.toml";
      in
      lib.hm.dag.entryAfter ["writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/${target_path_postfix}" ] || ln -sf "$NIXOS_CONFIG/home/config/${target_path_postfix}" "$XDG_CONFIG_HOME/${target_path_postfix}"
		'';
		wallpaper_carousel = 
      let
        target_path_postfix = "wallpaper_carousel.nix";
      in
      lib.hm.dag.entryAfter ["writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/${target_path_postfix}" ] || ln -sf "$NIXOS_CONFIG/home/config/${target_path_postfix}" "$XDG_CONFIG_HOME/${target_path_postfix}"
		'';
  };
}
