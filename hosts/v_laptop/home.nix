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
  mylib,
  myvars,
  ...
}: {
  home.username = myvars.username;
  home.homeDirectory = "/home/${myvars.username}";

  #nix.extraOptions = "include ${config.home.homeDirectory}/s/g/private/sops.conf";
  #sops = {
  #	defaultSopsFile = "${config.home.homeDirectory}/s/g/private/sops.yaml";
  #};

  #defaultSopsFile = /home/v/s/g/private/sops.json;
  #defaultSopsFormat = "json";

  # # to be moved to shared (once I figure out how to source it)
  programs = {
    neovim = {
      defaultEditor = true; # sets $EDITOR
      #? Can I get a nano alias?
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
    };
    direnv.enable = true;
    eza.enable = true;
  };
  home.sessionPath = [
    "${pkgs.lib.makeBinPath []}"
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

  dconf = {
    enable = true;
    settings."org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
  #

  #imports = [
  #  ../../home/config/fish/default.nix
  #];

  # fuck mkOutOfStoreSymlink and home-manager. Just link everything except for where apps like to write artifacts to the config dir.
  home.activation = {
    nvim = lib.hm.dag.entryAfter ["writeBoundary"] ''
      [ -e "$XDG_CONFIG_HOME/nvim" ] || ln -sf "$NIXOS_CONFIG/home/config/nvim" "$XDG_CONFIG_HOME/nvim"
    '';
    eww = lib.hm.dag.entryAfter ["writeBoundary"] ''
      [ -e "$XDG_CONFIG_HOME/eww" ] || ln -sf "$NIXOS_CONFIG/home/config/eww" "$XDG_CONFIG_HOME/eww"
    '';
    zathura = lib.hm.dag.entryAfter ["writeBoundary"] ''
      [ -e "$XDG_CONFIG_HOME/zathura" ] || ln -sf "$NIXOS_CONFIG/home/config/zathura" "$XDG_CONFIG_HOME/zathura"
    '';
    sway = lib.hm.dag.entryAfter ["writeBoundary"] ''
      [ -e "$XDG_CONFIG_HOME/sway" ] || ln -sf "$NIXOS_CONFIG/home/config/sway" "$XDG_CONFIG_HOME/sway"
    '';
    alacritty = lib.hm.dag.entryAfter ["writeBoundary"] ''
      [ -e "$XDG_CONFIG_HOME/alacritty" ] || ln -sf "$NIXOS_CONFIG/home/config/alacritty" "$XDG_CONFIG_HOME/alacritty"
    '';
    keyd = lib.hm.dag.entryAfter ["writeBoundary"] ''
      [ -e "$XDG_CONFIG_HOME/keyd" ] || ln -sf "$NIXOS_CONFIG/home/config/keyd" "$XDG_CONFIG_HOME/keyd"
    '';
    mako = lib.hm.dag.entryAfter ["writeBoundary"] ''
      [ -e "$XDG_CONFIG_HOME/mako" ] || ln -sf "$NIXOS_CONFIG/home/config/mako" "$XDG_CONFIG_HOME/mako"
    '';
    direnv = lib.hm.dag.entryAfter ["writeBoundary"] ''
      [ -e "$XDG_CONFIG_HOME/direnv" ] || ln -sf "$NIXOS_CONFIG/home/config/direnv" "$XDG_CONFIG_HOME/direnv"
    '';
    vesktop_settings_dir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      [ -e "$XDG_CONFIG_HOME/vesktop/settings" ] || ln -sf "$NIXOS_CONFIG/home/config/vesktop/settings" "$XDG_CONFIG_HOME/vesktop/settings"
    '';

    # # my file arch consequences
    mkdir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p $HOME/tmp/
      mkdir -p $HOME/Videos/obs/
      mkdir -p $HOME/tmp/Screenshots/
    '';
    #

    # ind files
    vesktop_settings_file = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ln -sf $NIXOS_CONFIG/home/config/vesktop/settings.json $XDG_CONFIG_HOME/vesktop/settings.json
    '';
    tg = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ln -sf $NIXOS_CONFIG/home/config/tg.toml $XDG_CONFIG_HOME/tg.toml
    '';
    tg_admin = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ln -sf $NIXOS_CONFIG/home/config/tg_admin.toml $XDG_CONFIG_HOME/tg_admin.toml
    '';
    auto_redshift = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ln -sf $NIXOS_CONFIG/home/config/auto_redshift.toml $XDG_CONFIG_HOME/auto_redshift.toml
    '';
    todo = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ln -sf $NIXOS_CONFIG/home/config/todo.toml $XDG_CONFIG_HOME/todo.toml
    '';
    discretionary_engine = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ln -sf $NIXOS_CONFIG/home/config/discretionary_engine.toml $XDG_CONFIG_HOME/discretionary_engine.toml
    '';
    btc_line = lib.hm.dag.entryAfter ["writeBoundary"] ''
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
  };

  # Things that never need to be available with sudo
  home.packages = with pkgs;
    lib.lists.flatten
    [
      cowsay
      unimatrix
      spotify
      #spotube // spotify-adblock is perfectly sufficient
      nyxt
      en-croissant # chess analysis GUI
      [
        # messengers
        telegram-desktop
        vesktop
        discord # for when vesktop breaks, otherwise vesktop is a superset
        zulip
      ]
      rnote
      zathura # read PDFs
      pdfgrep
      xournalpp # draw on PDFs
      ncspot
      neomutt
      anyrun # wayland-native rust alternative to rofi
      neofetch
      figlet
      [
        # auth
        oath-toolkit # https://askubuntu.com/questions/1460640/generating-totp-for-2fa-directly-from-the-computer-no-mobile-device
        bitwarden-desktop # seems like bitwarden is lacking TOTP on free plans
        bitwarden-cli
        keepassxc
        #TODO: attempt to maybe start using it. Or just go agenix/sops. Current system is rather fragile. Priority is low because currently there isn't much to protect.
        pass # linux password manager
        prs # some password manager in rust
        passh # non-interactive SSH auth
      ]
      [
        # RDP clients
        remmina
        anydesk # works to manage windows/linux+X11, but obviously can't RDP linux running wayland
        freerdp
      ]
      #flutterPackages-source.stable // errors
      typioca # tui monkeytype
      smassh # tui monkeytype
    ]
    ++ [
      inputs.auto_redshift.packages.${pkgs.system}.default
      inputs.todo.packages.${pkgs.system}.default
      inputs.booktyping.packages.${pkgs.system}.default
      inputs.btc_line.packages.${pkgs.system}.default
      inputs.tg.packages.${pkgs.system}.default
      inputs.bbeats.packages.${pkgs.system}.default
      #inputs.prettify_log.packages.${pkgs.system}.default
      inputs.distributions.packages.${pkgs.system}.default
      inputs.bad_apple_rs.packages.${pkgs.system}.default
      inputs.reasonable_envsubst.packages.${pkgs.system}.default

      #inputs.aggr_orderbook.packages.${pkgs.system}.default
      #inputs.orderbook_3d.packages.${pkgs.system}.default
    ]
    ++ [
      #nixpkgs-stable.telegram-desktop
      #inputs.nltch.spotify-adblock
      #inputs.nltch.ciscoPacketTracer8
      #self.packages.x86_64-linux.wlr-gamma-service
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

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    x11 = {
      enable = true;
      defaultCursor = "Adwaita";
    };
  };

  home.keyboard = null; # otherwise it overwrites my semimak

  programs = {
    yazi.enable = true;

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
  #home.stateVersion = "24.05"; # NB: DO NOT CHANGE, same as `system.stateVersion`
}
