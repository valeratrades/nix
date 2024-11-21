#TODO!: move much of this to shared dirs

#{
#  self,
#  ...
#}: {
#  config,
#  pkgs,
#  lib,
#  ...
#}:

{
  self,
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  home.username = "v";
  home.homeDirectory = "/home/v";

  #nix.extraOptions = "include ${config.home.homeDirectory}/s/g/private/sops.conf";
  #sops = {
  #	defaultSopsFile = "${config.home.homeDirectory}/s/g/private/sops.yaml";
  #};

  #defaultSopsFile = /home/v/s/g/private/sops.json;
  #defaultSopsFormat = "json";

  imports = [
    ../../home/config/fish/default.nix
  ];

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
    git = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/git" ] || ln -sf "$NIXOS_CONFIG/home/config/git" "$XDG_CONFIG_HOME/git"
    '';
    direnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/direnv" ] || ln -sf "$NIXOS_CONFIG/home/config/direnv" "$XDG_CONFIG_HOME/direnv"
    '';
    vesktop_settings_dir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -e "$XDG_CONFIG_HOME/vesktop/settings" ] || ln -sf "$NIXOS_CONFIG/home/config/vesktop/settings" "$XDG_CONFIG_HOME/vesktop/settings"
    '';

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
    "t/README.md".source = "${self}/home/fs/t/README.md";
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
    ".config/zsh" = {
      source = "${self}/home/config/zsh";
      recursive = true;
    };

    # configured via home-manager, so mixing it wouldn't work. Might want to just completely ditch hm with it though.
    ".config/tmux" = {
      source = "${self}/home/config/tmux";
      recursive = true;
    };

    ".cargo" = {
      source = "${self}/home/config/cargo";
      recursive = true;
    };
    "/usr/share/X11/xkb/symbols" = {
      source = "${self}/home/config/xkb_symbols";
      recursive = true;
    };
  };

  # link the configuration file in current directory to the specified location in home directory
  # home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;

  # link all files in `./scripts` to `~/.config/i3/scripts`
  # home.file.".config/i3/scripts" = {
  #   source = ./scripts;
  #   recursive = true;   # link recursively
  #   executable = true;  # make all files executable
  # };

  # encode the file content in nix configuration file directly
  # home.file.".xxx".text = ''
  #     xxx
  # '';

  # Things that never need to be available with sudo
  home.packages =
    with pkgs;
    # lib.flatten
    [
      cowsay
      unimatrix
      spotify
      spotube
      nyxt
			en-croissant # chess analysis GUI
      telegram-desktop
      vesktop
      rnote
      zathura # read PDFs
			pdfgrep
			xournalpp # draw on PDFs
      ncspot
      neomutt
      neofetch
      figlet
			anydesk
			teamviewer
			#flutterPackages-source.stable // errors
      zulip
      bash-language-server
			typioca # tui monkeytype
			smassh # tui monkeytype
			yazi
    ] ++ [
      inputs.auto_redshift.packages.${pkgs.system}.default
      inputs.todo.packages.${pkgs.system}.default
      inputs.booktyping.packages.${pkgs.system}.default
      inputs.btc_line.packages.${pkgs.system}.default
      inputs.tg.packages.${pkgs.system}.default
      inputs.bbeats.packages.${pkgs.system}.default
      #inputs.prettify_log.packages.${pkgs.system}.default // errors for some reason
      inputs.distributions.packages.${pkgs.system}.default
      inputs.bad_apple_rs.packages.${pkgs.system}.default

      #inputs.aggr_orderbook.packages.${pkgs.system}.default
      #inputs.orderbook_3d.packages.${pkgs.system}.default
    ] ++ [
			#nixpkgs-stable.telegram-desktop
		];

  #home.packages = with nixpkgs-stable: [
  #	google-chrome
  #];

  gtk = {
    enable = true;
    theme = {
      name = "Materia-dark"; # dbg: want Adwaita-dark
      package = pkgs.materia-theme;
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    x11 = {
      enable = true;
      defaultCursor = "Adwaita";
    };
  };

  home.sessionPath = [
    "${pkgs.lib.makeBinPath [ ]}"
    "${config.home.homeDirectory}/s/evdev/"
    "${config.home.homeDirectory}/.cargo/bin/"
    "${config.home.homeDirectory}/go/bin/"
    "/usr/lib/rustup/bin/"
    "${config.home.homeDirectory}/.local/bin/"
    "${config.home.homeDirectory}/pkg/packages.modular.com_mojo/bin"
    "${config.home.homeDirectory}/.local/share/flatpak"
    "/usr/bin"
    "/var/lib/flatpak"
  ];

  programs = {
    direnv.enable = true;

    neovim = {
      defaultEditor = true; # sets $EDITOR
      #? Can I get a nano alias?
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
    };

    eza.enable = true;
		thefuck = {
			enable = true;
			#alias = "f"; # I guess also not yet implemented in hm
		};

    tmux = {
      # enable brings in additional configuration state, so don't enable
      enable = true; # dbg
      package = pkgs.tmux;
      # don't work without enable. But enable, again, brings a bunch of unrelated shit. So basically no plugins for me.
      plugins = with pkgs; [
        tmuxPlugins.resurrect # persist sessions
        tmuxPlugins.open # open files
        tmuxPlugins.copycat # enables regex
      ];
      extraConfig = "${self}/home/config/tmux/tmux.conf";
    };

    home-manager.enable = true; # let it manage itself
  };
  home.stateVersion = "24.05"; # NB: DO NOT CHANGE, same as `system.stateVersion`
}
