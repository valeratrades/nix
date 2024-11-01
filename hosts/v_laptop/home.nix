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
  pkgs,
  inputs,
  ...
}:
let
  nix_home = "../../home";
in
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

    ".config/nvim" = {
      source = "${self}/home/config/nvim";
      recursive = true;
    };
    ".config/eww" = {
      source = "${self}/home/config/eww";
      recursive = true;
    };
    ".config/zathura" = {
      source = "${self}/home/config/zathura";
      recursive = true;
    };
    ".config/sway" = {
      source = "${self}/home/config/sway";
      recursive = true;
    };

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

    ".config/alacritty" = {
      source = "${self}/home/config/alacritty";
      recursive = true;
    };
    ".config/tmux" = {
      source = "${self}/home/config/tmux";
      recursive = true;
    };
    ".config/keyd" = {
      source = "${self}/home/config/keyd";
      recursive = true;
    };
    ".cargo" = {
      source = "${self}/home/config/cargo";
      recursive = true;
    };
    "mako" = {
      source = "${self}/home/config/mako";
      recursive = true;
    };
    "git" = {
      source = "${self}/home/config/git";
      recursive = true;
    };
    # don't use it, here just for completeness
    "zsh" = {
      source = "${self}/home/config/zsh";
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
      telegram-desktop
      vesktop
      rnote
      zathura
      ncspot
      neomutt
      neofetch
      figlet
      zulip
      bash-language-server # needs unstable rn (2024/10/21)
    ]
    ++ [
      inputs.auto_redshift.packages.${pkgs.system}.default
      inputs.todo.packages.${pkgs.system}.default
      inputs.booktyping.packages.${pkgs.system}.default
      inputs.btc_line.packages.${pkgs.system}.default
      inputs.tg.packages.${pkgs.system}.default

      #inputs.aggr_orderbook.packages.${pkgs.system}.default
      #inputs.orderbook_3d.packages.${pkgs.system}.default
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

    tmux = {
			# enable brings in additional configuration state, so don't enable
			enable = true; #dbg
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
