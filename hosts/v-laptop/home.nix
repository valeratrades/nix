#TODO!: move much of this to shared dirs
{
  self,
  config,
  lib,
  pkgs,
  inputs,
  mylib,
  user,
  ...
}:
{
  #nix.extraOptions = "include ${config.home.homeDirectory}/s/g/private/sops.conf";
  #sops = {
  #	defaultSopsFile = "${config.home.homeDirectory}/s/g/private/sops.yaml";
  #};

  #defaultSopsFile = /home/v/s/g/private/sops.json;
  #defaultSopsFormat = "json";

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
    direnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/direnv" ] || ln -sf "$NIXOS_CONFIG/home/config/direnv" "$XDG_CONFIG_HOME/direnv"
    '';

    # # my file arch consequences
    mkdir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p $HOME/tmp/
      mkdir -p $HOME/Videos/obs/
      mkdir -p $HOME/tmp/Screenshots/
    '';
    #

    # ind files
    vesktop_settings_file = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ln -sf $NIXOS_CONFIG/home/config/vesktop/settings.json $XDG_CONFIG_HOME/vesktop/settings.json
    '';
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

  home.file = {
    # # fs
    "g/README.md".source = "${self}/home/fs/g/README.md$";
    "s/g/README.md".source = "${self}/home/fs/s/g/README.md";
    "s/l/README.md".source = "${self}/home/fs/s/l/README.md";
    "tmp/README.md".source = "${self}/home/fs/tmp/README.md";
    #

    ".config/tg.toml".source = "${self}/home/config/tg.toml";
    ".config/tg_admin.toml".source = "${self}/home/config/tg_admin.toml";
    ".config/auto_redshift.toml".source = "${self}/home/config/auto_redshift.toml";
    ".config/todo.toml".source = "${self}/home/config/todo.toml";
    ".config/discretionary_engine.toml".source = "${self}/home/config/discretionary_engine.toml";
    ".config/btc_line.toml".source = "${self}/home/config/btc_line.toml";

    ".lesskey".source = "${self}/home/config/lesskey";
    ".config/fish/conf.d/sway.fish".source = "${self}/home/config/fish/conf.d/sway.fish";
    ".config/greenclip.toml".source = "${self}/home/config/greenclip.toml";

    # # Might be able to join these, syntaxis should be similar
    ".config/vesktop" = {
      source = "${self}/home/config/vesktop";
      recursive = true;
    };
    ".config/discord" = {
      source = "${self}/home/config/discord";
      recursive = true;
    };
    #
    # don't use it, here just for completeness
    #".config/zsh" = {
    #	source = "${self}/home/config/zsh";
    #	recursive = true;
    #};

    # configured via home-manager, so mixing it wouldn't work. Might want to just completely ditch hm with it though.
    ".config/tmux" = {
      source = "${self}/home/config/tmux";
      recursive = true;
    };

    ".cargo" = {
      source = "${self}/home/config/cargo";
      recursive = true;
    };
  };

  # Things that never need to be available with sudo
  home.packages =
    with pkgs;
    lib.lists.flatten [
      nyxt
      en-croissant # chess analysis GUI
      ncspot
      #flutterPackages-source.stable // errors

      [
        # retarded games. Here only for Tima, TODO: remove from v right after the host config split.
        prismlauncher
        modrinth-app
        jdk23
      ]
    ]
    ++ [
      # some of my own packages are in shared, not everything is here
      inputs.btc_line.packages.${pkgs.system}.default
      #inputs.prettify_log.packages.${pkgs.system}.default
      inputs.distributions.packages.${pkgs.system}.default # ? shared?
      inputs.bad_apple_rs.packages.${pkgs.system}.default

      #inputs.aggr_orderbook.packages.${pkgs.system}.default
      #inputs.orderbook_3d.packages.${pkgs.system}.default
    ];
}
