# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  self,
  config,
  pkgs,
  lib,
  user,
  mylib,
  ...
}:
#TODO: add build script that cds in $XDG_DATA_HOME/nvim/lazy-telescope-fzf-native.nvim and runs `make`
let
  userHome = config.users.users."${user.username}".home;
  configRoot = "/home/${user.username}/nix"; # TODO!!!!!: have this be dynamic based on the actual dir where this config is currently located.

  modularHome = "${userHome}/.modular";
in
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs.config.packageOverrides = pkgs: {
    nur =
      import
        #IMPURE
        (builtins.fetchTarball {
          url = "https://github.com/nix-community/NUR/archive/master.tar.gz";
          #sha256 = "sha256:0766s5dr3cfcyf31krr3mc6sllb2a7qkv2gn78b6s5v4v2bs545l";
        })
        {
          inherit pkgs;
        };
  };

  services = {
    getty.autologinUser = user.username;
    xserver = {
      # # somehow this fixed the audio problem. Like huh, what, why???
      desktopManager.gnome.enable = true;
      #displayManager.gdm.enable = true; #NB: if you enable `xserver`, _must_ enable this too. Otherwise it will use default `lightdm`, which will log you out.
      enable = false;
      displayManager.startx.enable = true; # TEST
      #
      autorun = false; # no clue if it does anything if `enable = false`, but might as well keep it

      #layout = "us,ir";
      #xkbVariant = "latitude";
      #xkbOptions = "grp:alt_shift_toggle";

      xkb = {
        options = "grp:win_space_toggle";
        extraLayouts.semimak = {
          description = "Semimak for both keyboard standards";
          languages = [ "eng" ];
          symbolsFile = mylib.relativeToRoot "home/xkb_symbols/semimak";
        };
        layout = "semimak,ru,us";
        variant = (if user.userFullName == "Timur" then "ansi,," else "iso,,");
        #
      };
      autoRepeatDelay = 240; # doesn't do anything currently (could be reset by sway)
      autoRepeatInterval = 70; # doesn't do anything currently (could be reset by sway)
    };
    libinput = {
      enable = true;
      touchpad.tapping = true; # doesn't do anything currently (could be reset by sway)
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

    openssh = {
      enable = true;
      settings = {
        KbdInteractiveAuthentication = true;
        UseDns = true; # allows for using hostnames in authorized_keys
        X11Forwarding = true; # theoretically allows for use of graphical applications
        PermitRootLogin = "yes"; # HACK: security risk
      };
      #openFirewall = true; # auto-open specified ports in the firewall. Seems to conflict with manual specification of eg `22` port
    };
    blueman.enable = true;
    gvfs.enable = true; # Mount, trash, and other functionalities
    tumbler.enable = true; # Thumbnail support for images
    geoclue2.enable = true; # Enable geolocation services.
    printing.enable = true; # Enable CUPS to print documents.
  };
  programs = {
    firefox.enable = true;
    sway = {
      enable = true;
      wrapperFeatures.gtk = true;
      extraSessionCommands = ''
        				export XDG_CURRENT_DESKTOP="sway";
        				export GDK_BACKEND="wayland";
        				export XDG_BACKEND="wayland";
        				export QT_WAYLAND_FORCE_DPI="physical";
        				export QT_QPA_PLATFORM="wayland-egl";
        				export CLUTTER_BACKEND="wayland";
        				export SDL_VIDEODRIVER="wayland";
        				export BEMENU_BACKEND="wayland";
        				export MOZ_ENABLE_WAYLAND="1";
        				# QT (needs qt5.qtwayland in systemPackages)
        				export QT_QPA_PLATFORM=wayland-egl
        				export SDL_VIDEODRIVER=wayland
        			'';
    };
    sway.xwayland.enable = true;
    fish.enable = true;

    # conflicts with gnupg agent on which I have ssh support. TODO: figure out which one I want
    ssh = {
      startAgent = true; # openssh remembers private keys; `ssh-add` adds a key to the agent
      enableAskPassword = true;
      extraConfig = ''
        PasswordAuthentication = yes
      '';
    };
    rust-motd.enableMotdInSSHD = true; # better ssh greeter
    mtr.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = false;
    };
    nh = {
      enable = true;
      clean = {
        enable = true;
        dates = "weekly";
        extraArgs = "--keep-since 7d";
      };
    };
    git = {
      enable = true;
      config = {
        user = {
          name = user.defaultUsername;
          email = user.defaultUserEmail;
          token = "$GITHUB_KEY"; # can't name `GITHUB_TOKEN`, as `gh` gets confused
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
          excludesfile = "${userHome}.config/git/.gitignore_global"; # converts any large files that were not included into .gitignore into pointers
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

        alias =
          let
            diff_ignore = ":!package-lock.json :!yarn.lock :!Cargo.lock :!flake.lock";
          in
          {
            # NB: git "aliases" must be self-contained. Say `am = commit -am` won't work.
            m = "merge";
            r = "rebase";
            d = "diff -- ${diff_ignore}";
            ds = "diff --staged -- ${diff_ignore}";
            s = "diff --stat -- ${diff_ignore}";
            sm = "diff --stat master -- ${diff_ignore}";
            l = "branch --list";
            unstage = "reset HEAD --"; # in case you did `git add .` before running `git diff`
            last = "log -1 HEAD";
            a = "add";
            aa = "add -A";
            au = "remote add upstream";
            ao = "remote add origin";
            su = "remote set-url upstream";
            so = "remote set-url origin";
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
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
      xdg-desktop-portal-shana
      dolphin # dbg: trying to figure out switching default file-chooser. First step is one that definitely works, Second is switching to my nvim wrapper
      lxqt.xdg-desktop-portal-lxqt
    ];
    wlr.enable = true;
  };

  imports = [
    ./desktop
    (mylib.relativeToRoot "./hosts/${user.desktopHostName}/configuration.nix")
    (
      if builtins.pathExists "/etc/nixos/hardware-configuration.nix" then
        /etc/nixos/hardware-configuration.nix
      else
        builtins.trace
          "WARNING: Falling back to ./hosts/${user.desktopHostName}/hardware-configuration.nix as /etc/nixos/hardware-configuration.nix does not exist. Likely to cause problems."
          mylib.relativeToRoot
          "./hosts/${user.desktopHostName}/hardware-configuration.nix"
    )
  ];
  #hardware.enableAllFirmware = true;

  # Bootloader.
  systemd.services.nix-daemon = {
    # https://github.com/NixOS/nixpkgs/pull/338181
    environment.TMPDIR = "/var/tmp";
  };
  boot = {
    tmp.useTmpfs = true;
    loader = {
      systemd-boot = {
        enable = true;
      };
      timeout = 0; # spam `Space` or `Shift` to bring the menu up when needed
      efi.canTouchEfiVariables = true;
      #grub.useOsProber = true; # need to find alternative for systemd-boot
    };

    # from what I understand, zswap is an intermediate layer with 3-4.3x compression in-RAM, to which older blocks are saved before being written to disk swap. Zram is the same, but no writes to disk at all, it just stays in the compressed RAM block. Don't want the latter, but former sounds promising.
    # not sure how to objectively check its effect on performance, though.
    kernelParams = [
      "zswap.enabled=1"
    ];

    # # for obs's Virtual Camera
    extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
    kernelModules = [
      "v4l2loopback"
      "binder-linux" # waydroid, nothing to do with obs (but I'm bad with nix, can't split them)
    ];
    extraModprobeConfig = ''
            options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
            options kvm_amd nested=1 # gnome-boxes require kvm
      			options binder-linux devices=binder,hwbinder,vndbinder # waydroid wants this
    '';
    #
  };

  # # waydroid
  # No, I can't fucking move it. Because there is still no good way to refer to config root, even with `mylib`
  #MANUAL:
  #- init with `sudo waydroid init -s GAPSS -f`
  #- patch google-play certificate: https://docs.waydro.id/faq/google-play-certification
  # normally setup also requires modyfiying waydroid_base.prop and starting up `systemctl wayland-container`, but these are taken care of below (theoretically).
  #// to use, do `waydroid show-full-ui`, currently also aliased with `wui`
  virtualisation = {
    waydroid.enable = true;
    lxd.enable = true;
  };
  system.activationScripts.patchWaydroid = {
    text = ''
      # if the patch was already appplied, testing reversing it (\`--dry-run -R\`) returns 0
      if ! ${pkgs.patch}/bin/patch --dry-run -R "/var/lib/waydroid/waydroid_base.prop" < "${configRoot}/os/nixos/desktop/waydroid/waydroid_base.prop.diff" >/dev/null 2>&1; then
        ${pkgs.patch}/bin/patch "/var/lib/waydroid/waydroid_base.prop" < "${configRoot}/os/nixos/desktop/waydroid/waydroid_base.prop.diff"
      fi
    '';
  };
  #

  time.timeZone = "UTC";
  i18n =
    if user.userFullName == "Timur" then
      {
        defaultLocale = "en_US.UTF-8"; # contemplated on making this `ru_RU.UTF-8`, but decided against it as that also affects outputs of some terminal commands, and that is just asking for developing bad habits.
        extraLocaleSettings = {
          LC_ADDRESS = "ru_RU.UTF-8";
          LC_IDENTIFICATION = "ru_RU.UTF-8";
          LC_MEASUREMENT = "ru_RU.UTF-8";
          LC_MONETARY = "ru_RU.UTF-8";
          LC_NAME = "ru_RU.UTF-8";
          LC_NUMERIC = "ru_RU.UTF-8";
          LC_PAPER = "ru_RU.UTF-8";
          LC_TELEPHONE = "ru_RU.UTF-8";
          LC_TIME = "ru_RU.UTF-8";
        };
      }
    else
      {
        defaultLocale = "en_US.UTF-8";
        extraLocaleSettings = {
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
      };

  hardware = {
    pulseaudio.enable = false;
    bluetooth.enable = true;
    bluetooth.powerOnBoot = false;
  };

  security = {
    sudo = {
      wheelNeedsPassword = false;
      enable = true;
    };
    rtkit.enable = true;
    polkit.enable = true;
  };

  users.users."${user.username}" = {
    isNormalUser = true;
    description = "${user.userFullName}";
    shell = pkgs.fish;
    extraGroups = [
      "networkmanager"
      "wheel"
      "keyd"
      "audio"
      "video"
    ];
    openssh.authorizedKeys.keys = user.sshAuthorizedKeys;
  };

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
    packages =
      with pkgs;
      lib.lists.flatten [
        cantarell-fonts
        dejavu_fonts
        source-code-pro # default monospace in GNOME
        source-sans
        agave
        corefonts
        dina-font
        emojione
        fira-code-symbols
        [
          # awesome
          font-awesome
          font-awesome_4
          font-awesome_5
        ]
        google-fonts
        ipafont
        [
          # nerd
          nerd-fonts.fira-code
          nerd-fonts.fira-mono
          nerd-fonts.hack
          nerd-fonts.noto
          nerd-fonts.ubuntu
          nerd-fonts.iosevka
          nerd-fonts.symbols-only
          nerd-fonts.jetbrains-mono
          nerd-fonts.code-new-roman
        ]
        julia-mono
        kanji-stroke-order-font
        liberation_ttf
        material-design-icons
        mplus-outline-fonts.githubRelease
        [
          # noto
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-emoji
        ]
        ocamlPackages.codicons
        powerline-fonts
        profont
        proggyfonts
        source-code-pro
        [
          # texlive
          texlivePackages.arimo
          texlivePackages.dejavu
          texlivePackages.fontawesome
          texlivePackages.fontawesome5
        ]
        ubuntu_font_family
      ]; # ++ (inputs.nixpkgs-2405.legacyPackages.${pkgs.system}.nerdfonts);
    fontconfig.enable = true;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nix.settings.download-buffer-size = "50G";

  environment = {
    # XDG directories and Wayland environment variables setup
    variables = {
      XDG_DATA_HOME = "${userHome}/.local/share";
      XDG_STATE_HOME = "${userHome}/.local/state";
      XDG_CONFIG_HOME = "${userHome}/.config";
      XDG_CACHE_HOME = "${userHome}/.cache";
      #XDG_RUNTIME_DIR is set by nix to /run/user/1000

      # Other specific environment variables
      GIT_CONFIG_HOME = "${userHome}/.config/git/config";
      QT_QPA_PLATFORMTHEME = "flatpak";
      GTK_USE_PORTAL = "1";
      GDK_DEBUG = "portals";

      # Nix
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
      WAKETIME = "6:00";
      DAY_SECTION_BORDERS = "2.5:10.5:16";
      DEFAULT_BROWSER = "${pkgs.google-chrome}/bin/google-chrome-stable";
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
        self.packages.${pkgs.system}.wlr-gamma-service
        libinput-gestures
        pkgs.qt5.full
        haskellPackages.greenclip
        lefthook # git hooks
        nerdfix # fixes illegal font codepoints https://discourse.nixos.org/t/nerd-fonts-only-see-half-the-icon-set/27513
        poppler_utils

        # nur plugs
        [
          nur.repos.nltch.spotify-adblock
        ]

        # emulators
        [
          #waydroid # might be auto-brought into the scope by `virtualization` module
          gnome-boxes # vm with linux distros
          # Windows
          [
            wineWowPackages.wayland
            #wineWowPackages.waylandFull
            #wineWowPackages.unstableFull
            winePackages.stagingFull
            #wine-staging # nightly wine
            winetricks # install deps for wine
            #bottles # ... python
            lutris # supposed to be more modern `playonlinux`. It's in python.
            playonlinux # oh wait, this shit's in python too
          ]
          # MacOS
          [
            #darling
            #dmg2img
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
          rust-motd
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
          wireguard-tools
          ngrok
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
          expect # automate things with interactive prompts
          tldr
          procs # `ps` in rust
          comma # auto nix-shell missing commands, so you can just `, cowsay hello`
          cowsay
          difftastic # better `diff`
          sudo-rs # `sudo` in rust
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
          yazi
        ]

        # terminals
        [
          starship
          alacritty
        ]

        # Networking Tools
        [
          openssh
          waypipe # similar to X11 forwarding, but for wayland
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
            nix-direnv
          ]
        ]

        # Coding
        [
          vscode-extensions.github.copilot
          mold-wrapped # probably shouldn't be here though
          sccache
          just
          toml-cli
          bash-language-server
          jdk23 # java dev kit (pray for my sanity)

          # editors
          [
            neovim
            #inputs.neovim-nightly-overlay.packages.${pkgs.system}.default #dbg: having some problems with treesitter
            vscode
          ]

          # language-specific
          [
            vscode-langservers-extracted # contains json lsp
            marksman # md lsp
            perl

            # Ocaml
            [
              ocaml
              ocamlPackages.ocaml-lsp
              ocamlPackages.findlib
              ocamlformat_0_22_4
              dune_3 # build system
              opam # package manager for ocaml
              opam-publish
            ]
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
              tinymist
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
              cargo-binstall # doesn't really work on nixos #? but could it work with fhs-compat layer?
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
              gccgo14
              clang-tools
              cmake
              gnumake
              meson
              ninja
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
      ]
    # ++ (inputs.nltch.legacyPackages.${pkgs.system}.spotify-adblock)
    ;
  };

  #TODO!: make specific to the host
  networking = {
    firewall = {
      enable = true;
      allowedTCPPorts = [
        80 # HTTP
        443 # HTTPS
        53 # DNS (some DNS services use TCP for large responses)
        22 # SSH
        23 # Telnet (legacy, just in case)
        21 # FTP (legacy, just in case)
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

    hostName = user.desktopHostName; # HACK: would not be for servers
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
