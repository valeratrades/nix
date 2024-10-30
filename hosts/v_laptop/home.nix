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
    "${config.home.homeDirectory}/g/README.md".source = "${self}/home/fs/g/README.md$";
    "${config.home.homeDirectory}/s/g/README.md".source = "${self}/home/fs/s/g/README.md";
    "${config.home.homeDirectory}/s/l/README.md".source = "${self}/home/fs/s/l/README.md";
    "${config.home.homeDirectory}/t/README.md".source = "${self}/home/fs/t/README.md";
    #

    "${config.home.homeDirectory}/.config/tg.toml".source = "${self}/home/config/tg.toml";
    "${config.home.homeDirectory}/.config/tg_admin.toml".source = "${self}/home/config/tg_admin.toml";
    "${config.home.homeDirectory}/.config/todo.toml".source = "${self}/home/config/todo.toml";
    "${config.home.homeDirectory}/.config/discretionary_engine.toml".source = "${self}/home/config/discretionary_engine.toml";
    "${config.home.homeDirectory}/.config/btc_line.toml".source = "${self}/home/config/btc_line.toml";
    "${config.home.homeDirectory}/.lesskey".source = "${self}/home/config/lesskey";
    "${config.home.homeDirectory}/.config/fish/conf.d/sway.fish".source = "${self}/home/config/fish/conf.d/sway.fish";

    "${config.home.homeDirectory}/.config/greenclip.toml".source = "${self}/home/config/greenclip.toml";

    "${config.home.homeDirectory}/.config/nvim" = {
      source = config.lib.file.mkOutOfStoreSymlink "${self}/home/config/nvim";
      recursive = true;
    };
    "${config.home.homeDirectory}/.config/eww" = {
      source = "${self}/home/config/eww";
      recursive = true;
    };
    "${config.home.homeDirectory}/.config/zathura" = {
      source = "${self}/home/config/zathura";
      recursive = true;
    };
    "${config.home.homeDirectory}/.config/sway" = {
      source = "${self}/home/config/sway";
      recursive = true;
    };

    # # Might be able to join these, syntaxis should be similar
    "${config.home.homeDirectory}/.config/vesktop" = {
      source = "${self}/home/config/vesktop";
      recursive = true;
    };
    "${config.home.homeDirectory}/.config/discord" = {
      source = "${self}/home/config/discord";
      recursive = true;
    };
    #

    "${config.home.homeDirectory}/.config/alacritty" = {
      source = "${self}/home/config/alacritty";
      recursive = true;
    };
    "${config.home.homeDirectory}/.config/keyd" = {
      source = "${self}/home/config/keyd";
      recursive = true;
    };
    "${config.home.homeDirectory}/.cargo" = {
      source = "${self}/home/config/cargo";
      recursive = true;
    };
    "${config.home.homeDirectory}/mako" = {
      source = "${self}/home/config/mako";
      recursive = true;
    };
    "${config.home.homeDirectory}/git" = {
      source = "${self}/home/config/git";
      recursive = true;
    };
    # don't use it, here just for completeness
    "${config.home.homeDirectory}/zsh" = {
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

  programs.direnv.enable = true;

  programs.neovim = {
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
  };

  programs.starship = {
    enable = true;
    #enableTransience = true;
    settings = {
      add_newline = false;
      aws.disabled = true;
      gcloud.disabled = true;
      line_break.disabled = true;

      #format = "$shlvl$shell$username$hostname$nix_shell$git_branch$git_commit$git_state$git_status$directory$jobs$cmd_duration$character";
      format = "$character";
      right_format = "$all";

      hostname = {
        style = "white";
        ssh_only = true;
      };
      shell = {
        disabled = false;
        format = "$indicator";
        fish_indicator = "";
        bash_indicator = "[BASH](bright-white) ";
        zsh_indicator = "[ZSH](bright-white) ";
      };
      nix_shell = {
        symbol = "";
        format = "[$symbol$name]($style) ";
        style = "bright-purple bold";
      };
      git_status = {
        style = "dim-green";
      };
      time = {
        format = "[$time]($style)";
        disabled = false;
      };
      rust = {
        format = "[$version]($style)";
      };
    };
  };
  # taken from https://github.com/tejing1/nixos-config/tree/master
  # programs.starship.settings = {
  #  add_newline = false;
  #  format = "$shlvl$shell$username$hostname$nix_shell$git_branch$git_commit$git_state$git_status$directory$jobs$cmd_duration$character";
  #  shlvl = {
  #    disabled = false;
  #    symbol = "ﰬ";
  #    style = "bright-red bold";
  #  };
  #  username = {
  #    style_user = "bright-white bold";
  #    style_root = "bright-red bold";
  #  };
  #  git_branch = {
  #    only_attached = true;
  #    format = "[$symbol$branch]($style) ";
  #    symbol = "שׂ";
  #    style = "bright-yellow bold";
  #  };
  #  git_commit = {
  #    only_detached = true;
  #    format = "[ﰖ$hash]($style) ";
  #    style = "bright-yellow bold";
  #  };
  #  git_state = {
  #    style = "bright-purple bold";
  #  };
  #  directory = {
  #    read_only = " ";
  #    truncation_length = 0;
  #  };
  #  cmd_duration = {
  #    format = "[$duration]($style) ";
  #    style = "bright-blue";
  #  };
  #  jobs = {
  #    style = "bright-green bold";
  #  };
  #  character = {
  #    success_symbol = "[\\$](bright-green bold)";
  #    error_symbol = "[\\$](bright-red bold)";
  #  };
  #};
  #
  #
  programs.home-manager.enable = true; # let it manage itself
  home.stateVersion = "24.05"; # NB: DO NOT CHANGE, same as `system.stateVersion`
}
