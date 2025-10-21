# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').
{ self, config, pkgs, lib, user, mylib, inputs, ... }:
#TODO: add build script that cds in $XDG_DATA_HOME/nvim/lazy-telescope-fzf-native.nvim and runs `make`
let
  userHome = config.users.users."${user.username}".home;
  configRoot =
    "/home/${user.username}/nix"; # TODO!!!!!: have this be dynamic based on the actual dir where this config is currently located.

  modularHome = "${userHome}/.modular";
in {
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
    ];
  };

  services = {
    gnome.gnome-keyring.enable = lib.mkDefault
      false; # annoying // Supposed to be an extra layer of security for managed {ssh passwords, gpg, wifi, etc}
  };
  virtualisation = {
    docker = {
      enable = true;
      package = pkgs.docker;
    };
  };
  programs = {
    #steam.enable = true; # brings steam-run # currently fails due to ocaml5 (2025/04/27)
  };

  imports = [
    (mylib.relativeToRoot "home/config/fish/default.nix")
    ./shared
    ./shared-services.nix
    ./shared-programs.nix
    (if user.userFullName == "Server" then ./server.nix else ./desktop)
    (mylib.relativeToRoot "./hosts/${user.desktopHostName}/configuration.nix")
    (if builtins.pathExists "/etc/nixos/hardware-configuration.nix" then
      /etc/nixos/hardware-configuration.nix
    else
      builtins.trace
      "WARNING: Falling back to ./hosts/${user.desktopHostName}/hardware-configuration.nix, as /etc/nixos/hardware-configuration.nix does not exist. Could cause problems."
      mylib.relativeToRoot
      "./hosts/${user.desktopHostName}/hardware-configuration.nix")
  ];
	hardware = {
		enableAllFirmware = true; # Q: not sure if I need it
	};

  systemd = {
		services = {
			dlm.wantedBy = [ "multi-user.target" ];
			nix-daemon = {
			# https://github.com/NixOS/nixpkgs/pull/338181
			environment.TMPDIR = "/var/tmp";
			};
			"systemd-backlight@.service" = {
				enable = false;
				unitConfig.Mask = true;
			};
		};
  };
  boot = {
    tmp.useTmpfs = true;
    loader = {
      systemd-boot = { enable = true; };
      timeout = 0; # spam `Space` or `Shift` to bring the menu up when needed
      efi.canTouchEfiVariables = true;
      #grub.useOsProber = true; # need to find alternative for systemd-boot
    };

    # from what I understand, zswap is an intermediate layer with 3-4.3x compression in-RAM, to which older blocks are saved before being written to disk swap. Zram is the same, but no writes to disk at all, it just stays in the compressed RAM block. Don't want the latter, but former sounds promising.
    # not sure how to objectively check its effect on performance, though.
    kernelParams = [
			"zswap.enabled=1"
			"nvidia-drm.modeset=1"
			"mem_sleep_default=s2idle"
		];

    # # for obs's Virtual Camera
    extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
    kernelModules = [
      "v4l2loopback"
      #"binder-linux" # waydroid, nothing to do with obs (but I'm bad with nix, can't split them) #dbg: disabled waydroid for a moment
			"evdi" # only needed with displaylink
    ];
    extraModprobeConfig = ''
            options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
            options kvm_amd nested=1 # gnome-boxes require kvm
						''
			#dbg
			#+ ''options binder-linux devices=binder,hwbinder,vndbinder # waydroid wants this ''
			;
  };

  time.timeZone = "UTC";
  i18n = if user.userFullName == "Timur" then {
    defaultLocale =
      "en_US.UTF-8"; # contemplated on making this `ru_RU.UTF-8`, but decided against it as that also affects outputs of some terminal commands, and that is just asking for developing bad habits.
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
  } else {
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

  environment.etc."bluetooth/audio.conf".text = ''
    # theoretically should prevent it from choosing HSP/HFP over A2DP
    Disable=Headset
  '';

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
    extraGroups =
      [ "networkmanager" "wheel" "keyd" "audio" "video" "docker" "dialout" "postgres" ];
    openssh.authorizedKeys.keys = user.sshAuthorizedKeys;
  };

  systemd = {
    user.services = {
      # MPRIS integrates with `pause/play` AVRCP actions sent by headphones
      mpris-proxy = {
        after = [ "network.target" "sound.target" ];
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
    packages = with pkgs;
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
        #ocamlPackages.codicons #dbg: breaking fucking retarded rebuild evaluator with `error: Package 'ocaml5.3.0-virtual_dom-0.17.0' in /nix/store/707m8gfbdyxhg1sgkiw5x9zh84ya012r-source/pkgs/development/ocaml-modules/janestreet/0.17.nix:1977 is marked as broken, refusing to evaluate.`
        powerline-fonts
        profont
        proggyfonts
        source-code-pro
        [
          #texliveFull
          texlivePackages.arimo
          texlivePackages.dejavu
          texlivePackages.fontawesome
          texlivePackages.fontawesome5
					#texlivePackages.newcomputermodern # many papers use it #TEST: may be breaking eww
        ]
        ubuntu_font_family
      ];
    fontconfig.enable = true;
  };

  # Allow unfree packages
  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [ "electron-32.3.3" ];
    allowInsecurePredicate = pkg: true;
  };

  nix.settings.download-buffer-size = "50G";
	programs.neovim = {
		package = pkgs.neovim-unwrapped.override { lua = pkgs.luajit; };
	};

  #	neovim = import "${neovim-nightly}/flake/packages/neovim.nix" {
  #  inherit lib pkgs;
  #  neovim-src =
  #    let
  #      lock = lib.importJSON "${neovim-nightly}/flake.lock";
  #      nodeName = lock.nodes.root.inputs.neovim-src;
  #      input = lock.nodes.${nodeName}.locked;
  #    in
  #    pkgs.fetchFromGitHub {
  #      inherit (input) owner repo rev;
  #      hash = input.narHash;
  #    };
  #};
  documentation.dev.enable = true;
  documentation.man = {
    man-db.enable =
      false; # In order to enable to mandoc man-db has to be disabled.
    mandoc.enable = true;
  };
  environment = {
    # XDG directories and Wayland environment variables setup
    variables = let xdgDataHome = "${userHome}/.local/share";
    in {
      XDG_DATA_HOME = "${xdgDataHome}";
      XDG_STATE_HOME = "${userHome}/.local/state";
      XDG_CONFIG_HOME =
        "${userHome}/.config"; # NB: sops setup may break if it's not ~/.config
      XDG_CACHE_HOME = "${userHome}/.cache";
      #XDG_RUNTIME_DIR is set by nix to /run/user/1000

      # Other specific environment variables
      GIT_CONFIG_HOME = "${userHome}/.config/git/config";

      # Nix
      NIXOS_CONFIG = "${configRoot}";
      #TODO!: figure out how to procedurally disable [vesktop, tg] evokations via rofi, outside of preset times in my calendar
      DOT_DESKTOP = "${pkgs.home-manager}/share/applications";
      DIRENV_WARN_TIMEOUT = "1h";
      # openssl hurdle
      PKG_CONFIG_PATH =
        "${pkgs.openssl.dev}/lib/pkgconfig" + (if user.userFullName != "Server" then ":${pkgs.alsa-lib.dev}/lib/pkgconfig:${pkgs.wayland-scanner.bin}/bin" else ""); # :${pkgs.openssl}/lib"; # many of my rust scripts require it

      STARSHIP_LOG = "error"; # disable the pesky [WARN] messages

      # home vars
      MODULAR_HOME = "${modularHome}";
      #PATH = "${pkgs.lib.makeBinPath [ ]}:${userHome}/s/evdev/:${userHome}/.cargo/bin/:${userHome}/go/bin/:/usr/lib/rustup/bin/:${userHome}/.local/bin/:${modularHome}/pkg/packages.modular.com_mojo/bin:${userHome}/.local/share/flatpak:/var/lib/flatpak";
      EDITOR = "nvim";
      WAKETIME = "${user.wakeTime}";
      DAY_SECTION_BORDERS = "0.2:8.5:16";
      PAGER = "less";
      MANPAGER = "less";
      LESSHISTFILE = "-";
      HISTCONTROL = "ignorespace";

    };

    binsh = "${pkgs.dash}/bin/dash";

    systemPackages = with pkgs;
      lib.lists.flatten [
        librsvg
        age # secrets initial encoding
        sops # secrets mgmt
        nginx
        caddy
				act # run GHAs locally
				ntfs3g # `woeusb` depends on it

				memtester # test for RAM corruption
				memtest86-efi # not sure which one though

        # dbs
        [
          redis
					clickhouse
          #awscli2 #dbg: builds long
          postgresql
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

        # System Utilities
        [
          alsa-utils
          dbus
          pkgs.man-pages
          pkgs.man-pages-posix
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
          openvpn
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
					powertop
					upower
          lm_sensors # System sensor monitoring
          #ltrace # Library call monitoring #TEST
          strace # System call monitoring
          iftop # network monitoring
          iotop # io monitoring
          sysstat
        ]

        # Compression and Archiving
        [
          atool
          libjxl # jpeg-xl tools
          p7zip
          poppler_utils
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

        # Terminals + Editors + Shells
        [
          starship

					neovim
					luajitPackages.luarocks-nix # install some lua plugins as isolated packages
					vimPlugins.nvim-dap-python
					vimPlugins.luasnip
					vimPlugins.lean-nvim

          fish
          dash
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
          wkhtmltopdf
					texliveTeTeX # theoretically adds extensions to pandoc
        ]

        # Web/Network Interaction
        [
          httpie
          wget
          aria2
        ]

        # VC / deployment
        [
          gh
          git
          git-lfs # large file storage
          pkg-config # when used in build scripts, must be included in `nativeBuildInputs`. Only _native_ will work.
          openssl
          tokei

          # env / deployment
          [
            #docker
            docker-compose
            docker-compose-language-service
            docker-client
            arion # configure docker with nix
            podman-compose
            cargo-shuttle
            devenv
            nix-direnv
          ]
        ]
      ];
  };

  powerManagement = {
    enable = true;
  };

  #TODO!: make specific to the host
  networking = {
		nameservers = [ "8.8.8.8" "1.1.1.1" ];
		# Add hosts entries to bypass DNS issues with tailscale
		extraHosts = ''
			104.18.14.166 api.bitget.com
			104.18.15.166 api.bitget.com
		'';
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
        993 # IMAP (for himalaya)
        465 # SMTP (for himalaya)
      ];
      allowedUDPPorts = [
        53 # DNS
        67 # DHCP (client)
        68 # DHCP (server)
        123 # NTP (for time synchronization)
        5353 # mDNS (for local network service discovery)
        3478 # STUN (for NAT traversal, used in VoIP/WebRTC)
        1935 # RTMP (for streaming if required)
        993 # IMAP (for himalaya)
        465 # SMTP (for himalaya)
      ];

      # to transfer files from phone
      allowedTCPPortRanges = [{
        from = 1714;
        to = 1764;
      }];
      allowedUDPPortRanges = [{
        from = 1714;
        to = 1764;
      }];
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
    networkmanager = {
			dns = "none";
			enable = true;
		};
  };

  # replaced by `nh.clean`
  #nix.gc = {
  #  automatic = true;
  #  dates = "weekly";
  #  options = "--delete-older-than 1w";
  #};
  nix.settings.auto-optimise-store =
    true; # NB: can slow down individual builds; alternative: schedule optimise passes: https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-auto-optimise-store
  system.stateVersion = "24.05"; # NB: changing requires migration
}
