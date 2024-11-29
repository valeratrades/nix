# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  self,
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

#TODO: add build script that cds in $XDG_DATA_HOME/nvim/lazy-telescope-fzf-native.nvim and runs `make`

let
  userHome = config.users.users.v.home; #TODO: also should be dynamic
  configRoot = "/home/v/nix"; #TODO!!!!!: have this be dynamic

  modularHome = "${userHome}/.modular";

  systemdCat = "${pkgs.systemd}/bin/systemd-cat";
  sway = "${config.programs.sway.package}/bin/sway";
in
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs.config.packageOverrides = pkgs: {
    nur =
      import
        (builtins.fetchTarball {
          url = "https://github.com/nix-community/NUR/archive/master.tar.gz";
          #sha256 = "sha256:0766s5dr3cfcyf31krr3mc6sllb2a7qkv2gn78b6s5v4v2bs545l";
        })
        {
          inherit pkgs;
        };
  };

	#environment.etc."systemd/system/wlr-gamma-service.service" = {
	#	source = ../modules/wlr-brightness/res/wlr-gamma-service.service;
	#	mode = "0644";
	#};
	#systemd.services.wlr-gamma-service = {
 #   description = "WLR Gamma Service";
 #   wantedBy = [ "multi-user.target" ];
 #   serviceConfig.ExecStart = "${pkgs.wlr-gamma-service}/bin/wlr-gamma-service";  # Adjust if the binary path differs
 # };

  services = {
    xserver = {
      # # somehow this fixed the audio problem. Like huh, what, why???
      desktopManager.gnome.enable = true;
      #displayManager.gdm.enable = true; #NB: if you enable `xserver`, _must_ enable this too. Otherwise it will use default `lightdm`, which will log you out.
      enable = false;
      #
      autorun = false; # no clue if it does anything if `enable = false`, but might as well keep it
      #TODO!!!!!!!!!: update to actually install semimak there first.
      xkb = {
        #dir = lib.mkDefault "/etc/nixos/X11/xkb"; # Changing the root dir does not work. It must be exactly where expected or xkb goes nuts.
        options = "grp:win_space_toggle";

        # # selecting the following doesn't change anything though, must be configured through sway (or so I think now)
        extraLayouts.semimak = {
          description = "Semimak for both keyboard standards";
          languages = [ "eng" ];
          symbolsFile = ../xkb/symbols/semimak;
        };
        layout = "semimak";
        variant = "iso";
        #
      };
    };

    pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
      jack.enable = true;
      wireplumber.enable = true;
    };

    keyd.enable = true;
    printing.enable = true;
    libinput.enable = true;
    openssh.enable = true;
    blueman.enable = true;
  };
  programs = {
    firefox.enable = true;
    sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };
    sway.xwayland.enable = true;
    fish.enable = true;

    mtr.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    nh = {
      enable = true;
      clean = {
        enable = true;
        dates = "weekly";
        extraArgs = "--keep-since 7d";
      };
    };
    starship = {
      # defined here, as `hm` doesn't yet recognize the `presets` option on `starship` (2024/10/31)
      presets = [ "no-runtime-versions" ]; # noisy on python, lua, and all the languages I don't care about. Would rather explicitly setup expansions on the important ones.
      settings = {
        # "no-runtime-versions" doesn't get rid of the `via` prefix, which almost makes it useless
        lua = {
          format = "[$symbol]($style) ";
        };
        typst = {
          format = "[$symbol]($style) ";
        };
        python = {
          format = "[$symbol(\($virtualenv\))]($style) "; # didn't get virtualenv to work yet
        };
        ocaml = {
          format = "[$symbol]($style) ";
        };
        ruby = {
          format = "[$symbol]($style) ";
        };
        nodejs = {
          format = "[$symbol]($style) ";
        };
        rust = {
          format = "[$version]($style) ";
          #version_format = "$major.$minor(-$toolchain)"; # $toolchain is not recognized correctly right now (2024/10/31)
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
          format = "[$symbol]($style) ";

          style = "bold blue";
          pure_msg = "";
          impure_msg = "[impure shell](yellow)";
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
        # Only useful for vim-mode, but I prefer to use my global vim keyd layer instead. Rest of this module is reimplemented with `status`.
        character = {
          disabled = true;
        };
        direnv = {
          format = "[$symbol$allowed]($style) ";
          symbol = " ";

          style = "bold basil";
          denied_msg = "-";
          not_allowed_msg = "~";
          allowed_msg = "+";

          #format = "[$symbol]($allowed) "; # starship is not smart enough. Leaving for if it gets better.
          #denied_msg = "purple";
          #not_allowed_msg = "bold red";
          #allowed_msg = "bold basil";

          disabled = false;
        };
        status = {
          # ? can I remake the `$character` with this?
          #success_symbol = "  "; # preserve indent
          format = "([$signal_name](bold flamingo) )$int $symbol"; # brackets around `signal_name` to not add whitespace when it's empty

          pipestatus = true;
          pipestatus_format = "\[$pipestatus\] => ([$signal_name](bold flamingo) )$int";

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

        #TODO!: sigure out how to quickly estimate the dir size, display here with `(gray)`
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
    git = {
      enable = true;
      config = {
        user = {
          #TODO!!!!: make the name and email dynamic
          #name = builtins.getEnv "GITHUB_USERNAME"; // doesn't work, fills empty
          name = "valeratrades";
          email = "v79166789533@gmail.com";
          password = "$GITHUB_KEY";
          token = "$GITHUB_TOKEN";
        };

        credential.helper = "store";

        pull = {
          rebase = true;
        };

        safe = {
          directory = "*"; # says it's okay to write anywhere
        };

        help = {
          autocorrect = 5;
        };

        core = {
          excludesfile = "/home/v/.config/git/.gitignore_global"; # converts any large files that were not included into .gitignore into pointers
        };

        pager = {
          difftool = true;
        };

        filter."lfs" = {
          clean = "git-lfs clean -- %f";
          smudge = "git-lfs smudge -- %f";
          process = "git-lfs filter-process";
          required = true;
        };

        fetch = {
          prune = true; # when deleting file locally, delete pointers on the remote
        };

        diff = {
          colorMoved = "zebra"; # copy/pastes are colored differently than actual removes/additions
          colormovedws = "allow-indentation-change";
          external = "/usr/bin/env difft --color auto --background light --display side-by-side";
        };

        advice = {
          detachedHead = true; # warn when pointing to a commit instead of branch
          addIgnoredFile = false;
        };

        alias = {
          # NB: git "aliases" must be self-contained. Say `am = commit -am` won't work.
          m = "merge";
          r = "rebase";
          d = "diff";
          ds = "diff --staged";
          s = "diff --stat";
          sm = "diff --stat master";
          l = "branch --list";
          unstage = "reset HEAD --"; # in case you did `git add .` before running `git diff`
          last = "log -1 HEAD";
          u = "remote add upstream";
          b = "branch";
          c = "checkout";
          cb = "checkout -b";
          f = "push --force-with-lease";
          p = "pull --rebase";
          blame = "blame -w -C -C -C";
          ca = "commit -am";
          ri = "rebase --autosquash -i master";
          ra = "rebase --abort";
          rc = "rebase --continue";
          log = "-c diff.external=difft log -p --ext-diff";
          stash = "stash --all";
          hardupdate = "!git fetch && git reset --hard \"origin/$(git rev-parse --abbrev-ref HEAD)\""; # stolen from Orion, but not yet tested
          noedit = "commit -a --amend --no-edit";
        };

        url."git@gist.github.com:" = {
          pushInsteadOf = "https://gist.github.com/";
        };

        # url."git@github.com:" = {
        #   pushInsteadOf = "https://github.com/";
        # };

        url."git@gitlab.com:" = {
          pushInsteadOf = "https://gitlab.com/";
        };

        init = {
          defaultBranch = "master";
        };

        push = {
          autoSetupRemote = true;
          default = "current";
        };

        rerere = {
          autoUpdate = true;
          enabled = true;
        };

        branch = {
          sort = "-committerdate";
          autoSetupMerge = "simple";
        };

        rebase = {
          autosquash = true;
        };

        merge = {
          conflictStyle = "zdiff3";
        };
      };
    };
  };
  xdg.portal.enable = true;
  xdg.portal.wlr.enable = true;

  imports = [
    ./hardware-configuration.nix
  ];
  #hardware.enableAllFirmware = true;

  # Bootloader.
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
      };
      timeout = 0; # spam `Space` or `Shift` to bring the menu up when needed
      efi.canTouchEfiVariables = true;
      #grub.useOsProber = true; # need to find alternative for systemd-boot
    };

    # # for obs's Virtual Camera
    extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
    kernelModules = [
      "v4l2loopback"
    ];
    extraModprobeConfig = ''
      				options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
      				options kvm_amd nested=1 # gnome-boxes require kvm
    '';
    #
  };

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  hardware = {
    pulseaudio.enable = false;
    bluetooth.enable = true;
    bluetooth.powerOnBoot = false;
  };

  security = {
    sudo = {
      enable = true;
      extraConfig = ''
        	%wheel ALL=(ALL) NOPASSWD: ALL
      '';
    };
    rtkit.enable = true;
    polkit.enable = true;
  };

  users.users.v = {
    isNormalUser = true;
    description = "v";
    shell = pkgs.fish;
    extraGroups = [
      "networkmanager"
      "wheel"
      "keyd"
      "audio"
      "video"
    ];
  };

  services.getty.autologinUser = "v";

  systemd = {
    user.services = {
      # not sure why I have this
      mpris-proxy = {
        description = "Mpris proxy";
        after = [
          "network.target"
          "sound.target"
        ];
        wantedBy = [ "default.target" ];
        serviceConfig.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
      };
      #start-ssh-port = {
      #  description = "Start SSH port forwarding on boot";
      #  wantedBy = [ "multi-user.target" ];
      #  serviceConfig = {
      #    ExecStart = ''
      #      #!/usr/bin/env sh
      #      [ -e "$XDG_CONFIG_HOME/nvim" ] || "
      #      PORT=2222 # Change this to your desired port
      #      ssh -f -N -L "$PORT:localhost:$PORT" user@remote_host
      #    '';
      #  };
      #  script = true;
      #};
    };
  };

  fonts = {
    #NB: many of the icons will be overwritten by nerd-fonts. If a character is not rendering properly, use `nerdfix` on the repo, search for correct codepoint in https://www.nerdfonts.com/cheat-sheet
    packages = with pkgs; [
      cantarell-fonts
      dejavu_fonts
      source-code-pro # default monospace in GNOME
      source-sans
      agave
      corefonts
      dejavu_fonts
      dina-font
      emojione
      fira-code
      fira-code-nerdfont
      fira-code-symbols
      font-awesome
      font-awesome_4
      font-awesome_5
      google-fonts
      ipafont
      jetbrains-mono
      julia-mono
      kanji-stroke-order-font
      liberation_ttf
      material-design-icons
      mplus-outline-fonts.githubRelease
      nerdfonts
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      ocamlPackages.codicons
      powerline-fonts
      profont
      proggyfonts
      source-code-pro
      texlivePackages.arimo
      texlivePackages.dejavu
      texlivePackages.fontawesome
      texlivePackages.fontawesome5
      ubuntu_font_family
    ];
    fontconfig.enable = true;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  environment = {
    # XDG directories and Wayland environment variables setup
    variables = {
      XDG_DATA_HOME = "${userHome}/.local/share";
      XDG_STATE_HOME = "${userHome}/.local/state";
      XDG_CONFIG_HOME = "${userHome}/.config";
      XDG_CACHE_HOME = "${userHome}/.cache";
			#XDG_RUNTIME_DIR is set by nix to /run/user/1000
      XDG_CURRENT_DESKTOP = "sway";
      GDK_BACKEND = "wayland";
      XDG_BACKEND = "wayland";
      QT_WAYLAND_FORCE_DPI = "physical";
      QT_QPA_PLATFORM = "wayland-egl";
      CLUTTER_BACKEND = "wayland";
      SDL_VIDEODRIVER = "wayland";
      BEMENU_BACKEND = "wayland";
      MOZ_ENABLE_WAYLAND = "1";

      # Other specific environment variables
      GIT_CONFIG_HOME = "${userHome}/.config/git/config";
      QT_QPA_PLATFORMTHEME = "flatpak";
      GTK_USE_PORTAL = "1";
      GDK_DEBUG = "portals";

      # Nix
      TEST = "${configRoot}"; # dbg
      NIXOS_CONFIG = "${configRoot}";
      #TODO!: figure out how to procedurally disable [vesktop, tg] evokations via rofi, outside of preset times in my calendar
      DOT_DESKTOP = "${pkgs.home-manager}/share/applications";
      DIRENV_WARN_TIMEOUT = "1h";
      # openssl hurdle
      PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.alsa-lib.dev}/lib/pkgconfig:${pkgs.wayland-scanner.bin}/bin"; # :${pkgs.openssl}/lib"; # many of my rust scripts require it
      #LD_PRELOAD = "${inputs.distributions.packages.${pkgs.system}.default}/lib/libspotifyadblock.so"; # really hoping I'm not breaking anything
      SPOTIFY_ADBLOCK_LIB = "${pkgs.nur.repos.nltch.spotify-adblock}/lib/spotify/libspotifyadblock.so"; # need to add it to `LD_PRELOAD` before starting spotify to get rid of adds
      #TODO: SPOTIFY_ADBLOCK_LIB = "${"github:nt-ltch/nur-packages#spotify-adblock"}/lib/spotify/libspotifyadblock.so"; # need to add it to `LD_PRELOAD` before starting spotify to get rid of adds

      # apparently wine works better on 32-bit
      #NB: when enabling, make sure the main monitor the wine will be displayed on starts at `0 0`
      WINEPREFIX = "${userHome}/.wine";
      #WINEARCH = "win32";

      # home vars
      MODULAR_HOME = "${modularHome}";
      #PATH = "${pkgs.lib.makeBinPath [ ]}:${userHome}/s/evdev/:${userHome}/.cargo/bin/:${userHome}/go/bin/:/usr/lib/rustup/bin/:${userHome}/.local/bin/:${modularHome}/pkg/packages.modular.com_mojo/bin:${userHome}/.local/share/flatpak:/var/lib/flatpak";
      EDITOR = "nvim";
      WAKETIME = "5:00";
      DAY_SECTION_BORDERS = "2.5:10.5:16";
      PAGER = "less";
      MANPAGER = "less";
      LESSHISTFILE = "-";
      HISTCONTROL = "ignorespace";
    };

    binsh = "${pkgs.dash}/bin/dash";

    #naersk
    #(naersk.buildPackage {
    #	src = "${userHome}/s/tg";
    #})
    #inputs.helix.packages."${pkgs.system}".helix
    #TODO!: make structure modular, using [flatten](<https://noogle.dev/f/lib/flatten>)
    systemPackages =
      with pkgs; # basically `use pkgs::*`
      lib.lists.flatten [
        granted # access cloud
        flatpak
        keyd
				self.packages.x86_64-linux.wlr-gamma-service
        libinput-gestures
        pkgs.qt5.full
        fractal # matrix chat protocol adapter
        xdg-desktop-portal-gtk # not sure if I even need it here, it's probably already brought into the scope by `xdg.portal.enable`
        haskellPackages.greenclip
        lefthook # git hooks
        wayland-scanner
        nerdfix # fixes illegal font codepoints https://discourse.nixos.org/t/nerd-fonts-only-see-half-the-icon-set/27513
        poppler_utils

        # nur plugs
        [
          nur.repos.nltch.spotify-adblock
        ]

        # emulators
        [
          waydroid
          gnome-boxes # vm with linux distros
          # Windows
          [
            wineWowPackages.wayland
            #wineWowPackages.waylandFull
            #wineWowPackages.unstableFull
            winePackages.stagingFull
            #wine-staging # nightly wine
            winetricks # install deps for wine
            bottles # ... python
            lutris # supposed to be more modern `playonlinux`. It's in python.
            playonlinux # oh wait, this shit's in python too
          ]
          # MacOS
          [
            darling
            dmg2img
          ]
        ]

        # gnome
        [
          xdg-user-dirs
          xdg-user-dirs-gtk
          glib
        ]

        # Nix
        [
          nh
          nix-index
          manix # grep nixpkgs docs
          nix-output-monitor
          cachix
        ]

        # UI/UX Utilities
        [
          adwaita-qt
          bemenu
          blueman
          eww
          grim
          slurp
          mako
          networkmanagerapplet
          rofi
          swappy
        ]

        # System Utilities
        [
          alsa-utils
          dbus
          hwinfo
          dconf
          file
          gsettings-desktop-schemas
          libnotify
          lm_sensors # for `sensors` command
          lsof
          pciutils # lspci
          sysstat
          usbutils # lsusb
          wireplumber
          wl-clipboard
          wl-gammactl
          xorg.xkbcomp
          xz
        ]

        # Network Tools
        [
          aria2 # better wget
          dnsutils # `dig` + `nslookup`
          ethtool
          iftop # network monitoring
          iotop # io monitoring
          ipcalc # IPv4/v6 address calculator
          iperf3
          mtr # Network diagnostic tool
          nmap # Network discovery/security auditing
          socat # replacement of openbsd-netcat
          iwd
          bettercap # man in the middle tool
          wireshark
          tshark # wireshark-cli
        ]

        # Monitoring and Performance
        [
          bottom
          lm_sensors # System sensor monitoring
          ltrace # Library call monitoring
          strace # System call monitoring
        ]

        # Compression and Archiving
        [
          atool
          p7zip
          unzip
          zip
          xz
          zstd
        ]

        # Command Line Enhancements
        [
          dust # `du` in rust
          atuin
          tldr
          procs # `ps` in rust
          comma # auto nix-shell missing commands, so you can just `, cowsay hello`
          cowsay
          difftastic # better `diff`
          cotp
          as-tree
          eza # better `ls`
          fd # better `find`
          bat # better `cat`
          ripgrep # better `grep`
          fzf
          jq
          tree
          zoxide
        ]

        # terminals
        [
          starship
          alacritty
        ]

        # Networking Tools
        [
          openssh
          bluez
          dnsutils
          ipcalc
          iperf3
          mtr
          nmap
          pciutils # lspci
          usbutils # lsusb
          wireplumber
        ]

        # File Utilities
        [
          fd # better `find`
          file
          gnupg
          gnused
          gnutar
          jq
          unzip
          zip
          pandoc
        ]

        # Audio/Video Utilities
        [
          pamixer
          easyeffects
          vlc
          pavucontrol
          pulseaudio
          pulsemixer
          #mov-cli // errors
          mpv
          chafa
          obs-cli
          ffmpeg

          # OBS
          [
            obs-studio
            (pkgs.wrapOBS {
              plugins = with pkgs.obs-studio-plugins; [
                wlrobs
                obs-backgroundremoval
              ];
            })
          ]
        ]

        # System Monitoring and Debugging
        [
          iftop # network monitoring
          iotop # io monitoring
          sysstat
          ltrace
          strace
        ]

        # Web/Network Interaction
        [
          httpie
          google-chrome
          chromium
          firefox
          wget
          aria2
        ]

        # shells
        [
          zsh
          fish
          fishPlugins.bass
          dash
        ]

        # Development Tools
        [
          gh
          git
          pkg-config # when used in build scripts, must be included in `nativeBuildInputs`. Only _native_ will work.
          openssl
          tokei

          # env
          [
            docker
            devenv
            direnv
          ]
        ]

        # Coding
        [
          vscode-extensions.github.copilot
          mold
          sccache
          just
          bash-language-server

          # editors
          [
            neovim
            vim
            vscode
          ]

          # language-specific
          [
            vscode-langservers-extracted # contains json lsp
            marksman # md lsp

            perl

            # Lean
            [
              #lean4 # want to use elan instead
              leanblueprint
              elan # rustup for lean. May or may not be outdated.
            ]
            # Js / Ts
            [
              nodejs_22
              deno
            ]

            # typst
            [
              typst
              typst-lsp
              typstyle # formatter
              typstfmt # only formats codeblocks
            ]
            # nix
            [
              nil # nix lsp
              niv # nix build dep management
              nix-diff
              statix # Lints and suggestions for the nix programming language
              deadnix # Find and remove unused code in .nix source files

              # formatters
              [
                nixfmt-rfc-style
                nixpkgs-fmt
                alejandra # Nix Code Formatter; not sure how it compares with nixpkgs-fmt
              ]
            ]
            # python
            [
              python312Packages.numpy
              python3
              python312Packages.pip
              python312Packages.jedi-language-server
              ruff
              ruff-lsp
            ]
            # golang
            [
              air # live reload
              go
              gopls
            ]
            # rust
            [
              # cargo, rustcs, etc are brought in by fenix.nix
              rustup
              crate2nix
              cargo-edit # cargo add command
              cargo-expand # expand macros
              cargo-hack
              cargo-udeps
              cargo-outdated
              cargo-rr
              cargo-tarpaulin
              cargo-sort # format Cargo.toml
              cargo-insta # snapshot tests
              cargo-mutants # fuzzy finding
              cargo-update
              #cargo-binstall # doesn't really work on nixos
              cargo-machete # detect unused
              cargo-release # automate release (has annoying req of having to commit _before_ this runs instead of my preffered way of pushing on success of release
              cargo-watch # auto-rerun `build` or `run` command on changes
              cargo-nextest # better tests
              cargo-limit # brings `lrun` and other `l$command` aliases for cargo, that suppress warnings if any errors are present.
            ]

            # C/C++
            [
              clang
              libgcc
              clang-tools
              cmake
              gnumake
            ]

            # lua
            [
              lua
              lua-language-server
            ]
          ]

          # Debuggers
          [
            lldb
            pkgs.llvmPackages.bintools
            vscode-extensions.vadimcn.vscode-lldb
          ]
        ]
      ]
      ++ [
      ] # ++ (inputs.nltch.legacyPackages.${pkgs.system}.spotify-adblock)
    ;
  };

  #TODO!: make specific to the host
  networking = {
    firewall = {
      allowedTCPPorts = [
        80 # HTTP
        443 # HTTPS
        53 # DNS (some DNS services use TCP for large responses)
        22 # SSH (if SSH access is needed)
        23 # Telnet (legacy, if required)
        21 # FTP (if needed for legacy protocols)
        554 # RTSP (for streaming media services)
        1935 # RTMP (often used for streaming)
        57621 # for Spotify
      ];
      allowedUDPPorts = [
        53 # DNS
        67 # DHCP (client)
        68 # DHCP (server)
        123 # NTP (for time synchronization)
        5353 # mDNS (for local network service discovery)
        3478 # STUN (for NAT traversal, used in VoIP/WebRTC)
        1935 # RTMP (for streaming if required)
        57621 # for Spotify
      ];

      # to transfer files from phone
      allowedTCPPortRanges = [
        {
          from = 1714;
          to = 1764;
        }
      ];
      allowedUDPPortRanges = [
        {
          from = 1714;
          to = 1764;
        }
      ];
      extraStopCommands = ''
        iptables -D nixos-fw -p tcp --source 192.0.2.0/24 --dport 1714:1764 -j nixos-fw-accept || true
        iptables -D nixos-fw -p udp --source 192.0.2.0/24 --dport 1714:1764 -j nixos-fw-accept || true
      '';
    };

    hostName = "v_laptop"; # should be set with home-manager
    # networking.proxy.default = "http://user:password@proxy:port/";
    # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

    # to setup network manager with uni wifi, you can 1) reference the `edit connection -> advanced options` on the phone (normally androids just work with them, then 2) edit accordingly with `nm-connection-editor`
    # on update of interface it can hang, btw, so `sudo systemctl restart NetworkManager` if `nmtui` does stops loading all networks
    networkmanager.enable = true;
  };

  # replaced by `nh.clean`
  #nix.gc = {
  #  automatic = true;
  #  dates = "weekly";
  #  options = "--delete-older-than 1w";
  #};
  nix.settings.auto-optimise-store = true; # NB: can slow down individual builds; alternative: schedule optimise passes: https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-auto-optimise-store
  system.stateVersion = "24.05"; # NB: changing requires migration
}
