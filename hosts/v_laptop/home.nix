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
    "${config.home.homeDirectory}/.config/auto_redshift.toml".source = "${self}/home/config/auto_redshift.toml";
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

  programs = {
    direnv.enable = true;

    neovim = {
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
    };

    eza.enable = true;

    starship = {
      #presets = [ "no-runtime-versions" ]; # noisy on python, lua, and all the languages I don't care about. Would rather explicitly setup expansions on the important ones.
      # for some reason doesn't work right now. Thus the manual setup block below. // part of it will persist even after fix, like `rust`
      settings = {
        python = {
          format = "[$symbol]($style)";
          #detect_folders = ["!.rs"];
        };
        lua = {
          format = "[$symbol]($style)";
        };
        rust = {
          format = "[$version]($style) ";
        };
      };

      enable = true;
      #enableTransience = true;
      settings = {
        # tipbits:
        # - `symbol` usually has a trailing whitespace
        add_newline = false;
        aws.disabled = true;
        gcloud.disabled = true;
        line_break.disabled = true;
        palette = "google_calendar";

        #format = "$username$character$\{custom.dbg\}";
        format = "$username$status$character";
        right_format = "$custom$all"; # `all` does _not_ duplicate explicitly enabled modules

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

          style = "bold blue";
          pure_msg = "";
        };
        git_branch = {
          format = "[$branch(:$remote_branch)]($style) ";
        };
        cmd_duration = {
          format = "[$duration]($style) ";
          style = "white";

          min_time = 2000; # milliseconds; min to display
          show_milliseconds = false;
          min_time_to_notify = 45000; # milliseconds
          #show_notifications = true; # produces noise on exiting `tmux`
        };
        time = {
          format = "[$time]($style)";
          disabled = false;
        };
        package = {
          disabled = true;
        };
        directory = {
          disabled = true;
          truncation_length = 0; # disables truncation
        };
        direnv = {
          symbol = " ";
          disabled = false;
        };
        # Only useful for vim-mode, but I prefer to use my global vim keyd layer instead. Rest of this module is reimplemented with `status`.
        character = {
          disabled = true;
        };
        status = {
          # ? can I remake the `$character` with this?
          #success_symbol = "  "; # preserve indent
          format = "([$signal_name](bold flamingo) )$int $symbol"; # brackets around `signal_name` to not add whitespace when it's empty

          pipestatus = true;

          success_symbol = "[❯ ](bold green)";
          symbol = "[❌](bold red)";
          not_executable_symbol = "[🚫](bold banana)";
          not_found_symbol = "[🔍](bold tangerine)";
          map_symbol = true;

          # we'll get indication from `$signal_name` anyways, this seems like clutter. //DEPRECATED in a month (2024/10/30)
          sigint_symbol = ""; # "[🧱](bright-red)";
          signal_symbol = ""; # [⚡](bold flamingo)";

          disabled = false;
        };
        shlvl = {
          format = "[$shlvl]($style) ";
          style = "bright-red";
          threshold = 3; # do most things from tmux, so otherwise carries no info
          disabled = false;
        };

        # if ordering is not forced, will be sorted alphabetically
        custom = {
          #shell = ["fish" "-c"]; # must be `fish`, but I didn't figure out how to enforce it yet
          path = {
            command = ''printf (prompt_pwd)'';
            when = ''true'';
            style = "bold cyan";
            shell = "fish";
          };
          readonly = {
            command = ''printf "🔒"'';
            when = ''! [ -w . ]'';
            style = "bold red";
          };
        };

        palettes.google_calendar = {
          lavender = "141";
          sage = "120";
          grape = "135";
          flamingo = "203";
          banana = "227";
          tangerine = "214";
          peacock = "39";
          graphite = "240";
          blueberry = "63";
          basil = "64";
          tomato = "160";
        };

      };
    };

    home-manager.enable = true; # let it manage itself
  };
  home.stateVersion = "24.05"; # NB: DO NOT CHANGE, same as `system.stateVersion`
}
