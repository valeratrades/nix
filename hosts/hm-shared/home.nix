{ self, config, lib, pkgs, user, inputs, ... }: {
  imports = [
    ./programs
    ./nixcord.nix
    (
      # in my own config I symlink stuff to fascilitate experimentation. In derived setups I value reproducibility much more
      if user.symlinkConfigs == true then
        ./config_symlinks.nix
      else
        (import ./config_writes.nix { inherit self pkgs user; }))
    # Import desktop services only for non-server users
    (if user.userFullName != "Server" then ./desktop-services.nix else null)
  ];
  #dbg: look at comment in ./config_symlinks.nix

  programs = {
    neovim = {
      plugins = [
        pkgs.vimPlugins.nvim-treesitter.withAllGrammars # can also choose specific ones with `.withPlugins (p: [ p.c p.java /*etc*/ ]))`
      ];
      defaultEditor = true; # sets $EDITOR
      #? Can I get a nano alias?
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
    };

    direnv = {
      enable = true;
      enableFishIntegration = true;
      package = pkgs.direnv;
      nix-direnv = {
        enable = true; # faster on nix
        package = pkgs.nix-direnv;
      };
      silent = true;
    };

    eza.enable = true;
    yazi.enable = true;
    # ref tmux config: https://github.com/Dich0tomy/snowstorm/blob/trunk/modules/home/tmux/default.nix
    tmux = {
      enable = true; # dbg
      keyMode = "vi";
      shortcut = "e";
      package = pkgs.tmux;
      plugins = with pkgs; [
        #tmuxPlugins.resurrect # persist sessions
        tmuxPlugins.open # open files
        tmuxPlugins.copycat # enables regex

        # [To save]: <prefix> + C-s
        {
          plugin = tmuxPlugins.resurrect;
          extraConfig = "set -g @resurrect-strategy-nvim 'session'";
        }
      ];
      extraConfig = "${self}/home/config/tmux/tmux.conf";
    };
    home-manager.enable = true; # let it manage itself
  };

  dconf = {
    enable = true;
    settings."org/gnome/desktop/interface" = { color-scheme = "prefer-dark"; };
  };

  gtk = {
    enable = true;
    theme = {
      name = "Materia-dark"; # dbg: want Adwaita-dark
      package = pkgs.materia-theme;
    };
  };

  #REF: example of working service setup here: https://github.com/nix-community/home-manager/blob/master/modules/services/polybar.nix

  systemd.user.services.eww-widgets = {
    Unit = {
      Description = "Start Eww Widgets";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
    Service = let
      eww = "${pkgs.eww}/bin/eww";
      script = pkgs.writeShellScript "eww-widgets-start" ''
        ${eww} open bar
        ${eww} open btc_line_lower
        ${eww} open btc_line_upper
        ${eww} open todo_blocker
      '';
    in {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${script}";
    };
  };

  systemd.user.services.wlr-gamma = {
    Unit = {
      Description = "wlroots Brightness Control";
      PartOf = "graphical-session.target";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
    Service = {
      Type = "simple";
      ExecStart = "${
          self.packages.${pkgs.system}.wlr-gamma-service
        }/bin/wlr-gamma-service";
    };
  };
  systemd.user.services.ssh-add-ed25119 = {
    Unit = { PartOf = "multi-user.target"; };
    Install = { WantedBy = [ "default.target" ]; };
    Service = {
      Type = "simple";
      ExecStart = "ssh-add ${config.home.homeDirectory}/.ssh/id_ed25519";
    };
  };

  auto_redshift = {
    enable = true;
    wakeTime = user.wakeTime;
  };

  home = {
    #FIXME: doesn't seem to work //Q: could it be because I have `fish.enable` inside the main configuration.nix, which overwrites this clean?
    sessionPath = [
      #"${pkgs.lib.makeBinPath [ ]}"
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
    pointerCursor = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      x11 = {
        enable = true;
        defaultCursor = "Adwaita";
      };
    };
    keyboard = null; # otherwise it overwrites my semimak

    # Things that never need to be available with sudo
    packages = with pkgs;
    # INFO: arrays are always automatically merged, in host-specfic `home.nix`s it may seem like I'm overwriting this, but it only looks this way.
      lib.lists.flatten [
        [
          # funsies
          unimatrix
          cowsay
          xdotool # most options don't work on wayland though
        ]
        [
          # messengers
          telegram-desktop
          element-desktop # GUI matrix client
          iamb # TUI matrix client (rust)
          zulip
        ]
        [
          # Desktop/GUI packages moved from configuration.nix
          libinput-gestures
          #qt5.full #dbg: brings in qtwebengine, which builds for too long
          google-chrome
          alacritty
        ]
        [
          # embedded dev
          #platformio-core #dbg: doesn't work rn for some reason
          #platformio #dbg: couldn't build the `pio` thing for some reason
          #arduino #dbg: can't build for some reason
          arduino-core
          arduino-ci
          arduino-mk
          arduino-ide
          arduino-language-server
          cargo-pio
          vscode-extensions.platformio.platformio-vscode-ide
          minicom
        ]
        [
          # Terminal apps/scripts (actually useful)
          typioca # tui monkeytype
          smassh # tui monkeytype
          fastfetch
          figlet
        ]
        [
          # nix
          nix-tree # analyse nix-store
        ]
        [
          # RDP clients (linux-to-linux doesn't really work)
          remmina
          anydesk # works to manage windows/linux+X11, but obviously can't RDP linux running wayland
          freerdp
        ]
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
        eww # info bar
        rnote # graphical notes
        qbittorrent # BitTorren gui
        transmission_4 # BitTorrent cli
        xdragon # drag-and-drop for X11 only
        neomutt # email client
        himalaya # email client but in rust
        fswebcam # instant webcam photo
        anyrun # wayland-native rust alternative to rofi
        zathura # read PDFs
        pdfgrep
        xournalpp # draw on PDFs
      ] ++ [
        inputs.auto_redshift.packages.${pkgs.system}.default # good idea for everyone
        inputs.todo.packages.${pkgs.system}.default # here, because eww depends on it, otherwise meant for my use exclusively
        inputs.bbeats.packages.${pkgs.system}.default
        inputs.reasonable_envsubst.packages.${pkgs.system}.default # have scripts depending on it, and they are currently part of the shared config.
        inputs.booktyping.packages.${pkgs.system}.default
      ];

    activation = {
      # # my file arch consequences
      mkdir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/tmp/
        mkdir -p $HOME/Videos/obs/
        mkdir -p $HOME/tmp/Screenshots/
      '';
      #
    };
    file = {
      # # fs
      "g/README.md".source = "${self}/home/fs/g/README.md$";
      "s/g/README.md".source = "${self}/home/fs/s/g/README.md";
      "s/l/README.md".source = "${self}/home/fs/s/l/README.md";
      "s/tmp/README.md".source = "${self}/home/fs/s/l/README.md";
      "tmp/README.md".source = "${self}/home/fs/tmp/README.md";
      #

      ".config/tg.toml".source = "${self}/home/config/tg.toml";
      ".config/tg_admin.toml".source = "${self}/home/config/tg_admin.toml";
      ".config/auto_redshift.toml".source = "${self}/home/config/auto_redshift.toml";
      ".config/discretionary_engine.toml".source = "${self}/home/config/discretionary_engine.toml";

      ".lesskey".source = "${self}/home/config/lesskey";
      ".config/fish/conf.d/sway.fish".source =
        "${self}/home/config/fish/conf.d/sway.fish";
      ".config/greenclip.toml".source = "${self}/home/config/greenclip.toml";

      ".config/iamb/config.toml".source = (pkgs.formats.toml { }).generate "" {
        default_profile = "master";
        profiles = {
          master = { user_id = "@${user.defaultUsername}:matrix.org"; };
        };
        macros = {
          normal = {
            s = "h";
            r = "j";
            n = "k";
            t = "l";

            gc = ":chats<Enter>";
            gd = ":dms<Enter>";
            gr = ":reply<Enter>";
            eh = ":react! heart<Enter>";
            eu = ":react! up<Enter>";
            ed = ":react! down<Enter>";

            "<M-c>" = "<C-w>q";
            "<C-w>v" = ":vsplit #alias:example.com<Enter>";
            "<C-w>h" = ":split #alias:example.com<Enter>";
          };
          command = { help = "welcome<Enter>"; };
        };
      };

      #".config/xdg-desktop-portal-shana/config.toml".source =
      #  (pkgs.formats.toml { }).generate
      #    "" {
      #      open_file = "org.freedesktop.desktop.impl.lxqt";
      #      save_file = "org.freedesktop.desktop.impl.lxqt";
      #    };
      #".config/xdg-desktop-portal/sway.conf".text = ''
      #  [preferred]
      #  default=dolphin
      #  org.freedesktop.impl.portal.Settings=dolphin
      #  #;gtk
      #  org.freedesktop.impl.portal.FileChooser=shana
      #  '';
      #        [portal]
      #DBusName=org.freedesktop.impl.portal.desktop.termfilechooser
      #Interfaces=org.freedesktop.impl.portal.FileChooser;
      #UseIn=i3;wlroots;sway;Wayfire;river;mate;lxde;openbox;unity;pantheon

      #TODO: figure out  (they have some bug on their side at the moment)
      #".config/direnv/direnv.toml".source = (pkgs.formats.toml { }).generate "" {
      #  global = {
      #    # https://github.com/direnv/direnv/issues/68#issuecomment-2054033048
      #    hide_env_diff = true;
      #  };
      #};

      #BUG: stupid `atuin` overwrites my generated config with a dummy one
      #dbg: \
       ".config/atuin/config.toml".source =
         (pkgs.formats.toml { }).generate "atuin.toml" {
           filter_mode_shell_up_key_binding =
             "directory"; # `_bind_up_search` will now only search in current dir
           sync.records = true;
           enter_accept = true;
         };

			#TEST: not certain, but it feels like this is somehow messing with it being able to persist `/login` state
			#".config/claude/config.json".source =
			#	(pkgs.formats.json { }).generate "claude.json" {
			#		completion_signal = {
			#			command = "notify-send %s";
			#			enabled = true;
			#			format = "{task_description}";
			#		};
			#		user_preferences = {
			#			notify_on_task_completion = true;
			#		};
			#	};

      # configured via hm, can't just symlink it in my host's config
      ".config/tmux" = {
        source = "${self}/home/config/tmux";
        recursive = true;
      };

      ".cargo" = {
        source = "${self}/home/config/cargo";
        recursive = true;
      };
			".config/zathura" = {
				source = "${self}/home/config/zathura";
				recursive = true;
			};
			".config/keyd" = {
				source = "${self}/home/config/keyd";
				recursive = true;
			};
			".config/mako" = {
				source = "${self}/home/config/mako";
				recursive = true;
			};
			".config/wireplumber" = {
				source = "${self}/home/config/wireplumber";
				recursive = true;
			};
		};
	};
}
