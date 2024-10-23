# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

#TODO: add build script that cds in $XDG_DATA_HOME/nvim/lazy-telescope-fzf-native.nvim and runs `make`

let
  userHome = config.users.users.v.home;

  modularHome = "${userHome}/.modular";

  systemdCat = "${pkgs.systemd}/bin/systemd-cat";
  sway = "${config.programs.sway.package}/bin/sway";
in
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  services = {
    xserver = {
      enable = false;
      autorun = false; # no clue if it does anything if `enable = false`, but might as well keep it
      xkb = {
        extraLayouts.semimak = {
          description = "Semimak for both keyboard standards";
          languages = [ "eng" ];
          symbolsFile = /usr/share/X11/xkb/symbols/semimak;
        };
        layout = "semimak";
        variant = "iso";
        options = "grp:win_space_toggle";
      };
    };
    #displayManager.enable = lib.mkForce false; # disables lightdm (hopefully)
    #displayManager.lightdm.enable = false; # disables lightdm (hopefully)

    keyd.enable = true;
    #xwayland.enable = true;

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

    printing.enable = true;
    libinput.enable = true;
    #openssh.enable = true;
    blueman.enable = true;
  };
  programs = {
    bash = {
      loginShellInit = ''
        if [ -z $DISPLAY ] && [ "$(tty)" = "/dev/tty4" ]; then
        	# https://wiki.archlinux.org/title/Sway#Automatically_on_TTY_login
        	#exec ${systemdCat} --identifier=sway ${sway}
        	exec /usr/bin/start_sway.sh
        fi
      '';
    };

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
  };
  xdg.portal.wlr.enable = true;

  imports = [
    ./hardware-configuration.nix
    #<home-manager/nixos>
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  #boot.loader.grub.useOsProber = true;

  # Set your time zone.
  time.timeZone = "Europe/Paris";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
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

  systemd = {
    #services = {
    #	"getty@tty1".enable = true;
    #	"autovt@tty1".enable = true;
    #};

    user.services.mpris-proxy = {
      description = "Mpris proxy";
      after = [
        "network.target"
        "sound.target"
      ];
      wantedBy = [ "default.target" ];
      serviceConfig.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
    };
  };

  fonts.packages = with pkgs; [
    nerdfonts
    font-awesome
    ocamlPackages.codicons
    corefonts
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji

    # # copied over for no particular reason:
    dejavu_fonts
    mplus-outline-fonts.githubRelease
    dina-font
    jetbrains-mono
    emojione
    fira-code
    fira-code-symbols
    font-awesome
    google-fonts
    ipafont
    kanji-stroke-order-font
    liberation_ttf
    mplus-outline-fonts.githubRelease
    powerline-fonts
    proggyfonts
    source-code-pro
    ubuntu_font_family
    #
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  environment = {
    # XDG directories and Wayland environment variables setup
    variables = {
      XDG_DATA_HOME = "${userHome}/.local/share";
      XDG_CONFIG_HOME = "${userHome}/.config";
      XDG_CACHE_HOME = "${userHome}/.cache";
      XDG_CURRENT_DESKTOP = "sway";
      QT_WAYLAND_FORCE_DPI = "physical";
      GDK_BACKEND = "wayland";
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

    shellInit = ''
      sudo ln -sfT ${pkgs.dash}/bin/dash /bin/sh
    '';

    #naersk
    #(naersk.buildPackage {
    #	src = "${userHome}/s/tg";
    #})
    #inputs.helix.packages."${pkgs.system}".helix
    #TODO!: make structure modular, using [flatten](<https://noogle.dev/f/lib/flatten>)
    systemPackages =
      with pkgs; # basically `use pkgs::*`
      lib.lists.flatten [
        # UI/UX Utilities
        [
          adwaita-qt
          bemenu
          blueman
          eww
          grim
          mako
          networkmanagerapplet
          rofi
          swappy
        ]

        # System Utilities
        [
          alsa-utils
          dbus
          dconf
          file
          gsettings-desktop-schemas
          libnotify
          lm_sensors # for `sensors` command
          lsof
          pamixer
          pavucontrol
          pciutils # lspci
          sysstat
          usbutils # lsusb
          which
          wireplumber
          wl-clipboard
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
          atuin
          babelfish
          cowsay
          cotp
          eza # better ‘ls’
          fd # better `find`
          alacritty
          fzf
          jq
          keyd
          ripgrep
          tree
          zoxide
        ]

        # Networking Tools
        [
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
          gnumake
          gnupg
          gnused
          gnutar
          jq
          unzip
          zip
        ]

        # Audio/Video Utilities
        [
          pamixer
          pavucontrol
          mpv
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
          wget
          aria2
        ]

        # Development Tools
        [
          cmake
          gh
          git
          glib
          pkg-config
          tokei
        ]

        # Unassigned
        [
          difftastic
          keyd
          libinput-gestures
          sccache
        ]

        # Coding
        [
          vscode-extensions.github.copilot
          mold
          sccache

          # editors
          [
            neovim
            vim
            vscode
          ]

          # shells
          [
            zsh
            fish
            fishPlugins.bass
            dash
          ]

          # language-specific
          [
            [
              nixfmt-rfc-style
              nil
              nix-diff
              nixpkgs-fmt
            ]
            # python
            [
              python3
              python312Packages.pip
              python312Packages.jedi-language-server
              ruff
              ruff-lsp
            ]
            # golang
            [
              go
              gopls
            ]
            # rust
            [
              cargo-edit
              cargo-sort
              cargo-mutants
              cargo-update
              cargo-machete
              cargo-watch
              cargo-nextest
              cargo-limit # brings `lrun` and other `l$command` aliases for cargo, that suppress warnings if any errors are present.
            ]

            # C/C++
            [
              clang
              clang-tools
            ]

            typst-lsp
            marksman # md lsp
          ]

          [
            lldb
            vscode-extensions.vadimcn.vscode-lldb
          ]
        ]
      ];
  };

  networking = {
    # for spotify:
    firewall.allowedTCPPorts = [
      57621 # for spotify
    ];
    firewall.allowedUDPPorts = [
      5353 # for spotify
    ];

    hostName = "nixos"; # Define your hostname.
    networkmanager.enable = true;
    # networking.proxy.default = "http://user:password@proxy:port/";
    # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 1w";
  };
  # https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-auto-optimise-store
  nix.settings.auto-optimise-store = true;
  system.stateVersion = "24.05"; # NB: changing requires migration
}
