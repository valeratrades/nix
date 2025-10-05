{ config, pkgs, lib, ... }:

let
  username = "nixos";
  userFullName = "Server";
  userHome = "/home/${username}";
  configRoot = "${userHome}/nix";
  redisPort = 49974;
  postgresqlPort = 52362;
in {
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal-combined.nix>
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services = {
    fstrim.enable = true;
    getty.autologinUser = username;

    redis.servers.default = {
      enable = true;
      port = redisPort;
    };

    postgresql = {
      enable = true;
      enableTCPIP = true;
      ensureUsers = [{
        name = "default";
        ensureClauses = {
          superuser = true;
          login = true;
        };
      }];
      ensureDatabases = [ "default" ];
      authentication = ''
        # TYPE  DATABASE        USER            ADDRESS                 METHOD
        local   all             all                                     trust
        host    all             all             127.0.0.1/32            trust
        host    all             all             ::1/128                 trust
      '';
      settings = {
        port = postgresqlPort;
        log_line_prefix = "[%p] ";
        logging_collector = true;
      };
    };

    clickhouse = {
      enable = true;
    };

    openssh = {
      enable = true;
      settings = {
        KbdInteractiveAuthentication = true;
        UseDns = true;
        X11Forwarding = false; # Not needed on servers
        PermitRootLogin = "yes";
      };
    };
  };

  virtualisation = {
    docker = {
      enable = true;
      package = pkgs.docker;
    };
  };

  programs = {
    fish.enable = true;
    ssh = {
      startAgent = true;
      enableAskPassword = true;
      extraConfig = ''
        PasswordAuthentication = yes
      '';
    };
    rust-motd.enableMotdInSSHD = true;
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
      # enable = true; # Already enabled by installation CD
      config = {
        user = {
          name = "Server User";
          email = "server@example.com";
          token = "$GITHUB_KEY";
        };
        credential.helper = "store";
        pull = { rebase = true; };
        safe = { directory = "*"; };
        help = { autocorrect = 5; };
        pager = { difftool = true; };
        filter = {
          "lfs" = {
            clean = "git-lfs clean -- %f";
            smudge = "git-lfs smudge -- %f";
            process = "git-lfs filter-process";
            required = true;
          };
        };
        fetch = { prune = true; };
        diff = {
          colorMoved = "zebra";
          colormovedws = "allow-indentation-change";
          external = "difft --color auto --background light --display side-by-side";
        };
        advice = {
          detachedHead = true;
          addIgnoredFile = false;
        };
        alias = let
          diff_ignore = ":!package-lock.json :!yarn.lock :!Cargo.lock :!flake.lock";
        in {
          m = "merge";
          r = "rebase";
          d = "--no-pager diff -- ${diff_ignore}";
          ds = "diff --staged -- ${diff_ignore}";
          s = "diff --stat -- ${diff_ignore}";
          sm = "diff --stat master -- ${diff_ignore}";
          l = "branch --list";
          unstage = "reset HEAD --";
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
          fp = "merge-base --fork-point HEAD";
          ca = "commit -am";
          ri = "rebase --autosquash -i master";
          ra = "rebase --abort";
          rc = "rebase --continue";
          log = "-c diff.external=difft log -p --ext-diff";
          stash = "stash --all";
          hardupdate = ''!git fetch && git reset --hard "origin/$(git rev-parse --abbrev-ref HEAD)"'';
          noedit = "commit -a --amend --no-edit";
        };
        url."git@gist.github.com:" = { pushInsteadOf = "https://gist.github.com/"; };
        url."git@gitlab.com:" = { pushInsteadOf = "https://gitlab.com/"; };
        init = { defaultBranch = "master"; };
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
        rebase = { autosquash = true; };
        merge = { conflictStyle = "zdiff3"; };
      };
    };
  };

  systemd = {
    services = {
      dlm.wantedBy = [ "multi-user.target" ];
      nix-daemon = {
        environment.TMPDIR = "/var/tmp";
      };
      setup-nixos-configs = {
        description = "Setup config files for nixos user";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
        };
        script = ''
          # Create nixos user home directory structure
          mkdir -p ${userHome}/.config

          # Copy config directories only if they don't exist
          [ ! -d ${userHome}/.config/fish ] && cp -r /etc/nixos-configs/fish ${userHome}/.config/
          [ ! -d ${userHome}/.config/nvim ] && cp -r /etc/nixos-configs/nvim ${userHome}/.config/
          [ ! -d ${userHome}/.config/cargo ] && cp -r /etc/nixos-configs/cargo ${userHome}/.config/
          [ ! -d ${userHome}/.config/helix ] && cp -r /etc/nixos-configs/helix ${userHome}/.config/
          [ ! -d ${userHome}/.config/nnn ] && cp -r /etc/nixos-configs/nnn ${userHome}/.config/
          [ ! -d ${userHome}/.config/tmux ] && cp -r /etc/nixos-configs/tmux ${userHome}/.config/
          [ ! -f ${userHome}/.lesskey ] && cp /etc/nixos-configs/lesskey ${userHome}/.lesskey

          # Fix ownership
          chown -R ${username}:users ${userHome}/.config ${userHome}/.lesskey 2>/dev/null || true
        '';
      };
    };
  };

  boot = {
    tmp.useTmpfs = true;
    loader.timeout = lib.mkForce 0; # Override installation CD timeout
    kernelParams = [
      "zswap.enabled=1"
      "mem_sleep_default=s2idle"
    ];
    kernel.sysctl."vm.overcommit_memory" = lib.mkForce "1"; # Fix Redis conflict with installation CD
  };

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  security = {
    sudo = {
      wheelNeedsPassword = false;
      enable = true;
    };
    rtkit.enable = true;
    polkit = {
      enable = true;
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.login1.reboot" ||
              action.id == "org.freedesktop.login1.power-off" ||
              action.id == "org.freedesktop.login1.halt") {
            if (subject.isInGroup("wheel")) {
              return polkit.Result.YES;
            }
          }
        });
      '';
    };
  };

  users.users."${username}" = {
    isNormalUser = true;
    description = userFullName;
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" "audio" "video" "docker" "dialout" "postgres" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEJA6PHRdXNysN/q8yYid3Vp3miFBB7a1441lOEHeOoZ valeratrades@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIz2m3ZyGSMog5x8GaboPfZqsuNqUO6E/031wks5eicU root@v-laptop"
    ];
  };

  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [ "electron-32.3.3" ];
    allowInsecurePredicate = pkg: true;
  };

  nix.settings.download-buffer-size = "50G";

  documentation.dev.enable = true;
  documentation.man = {
    man-db.enable = false;
    mandoc.enable = true;
  };

  environment = {
    variables = let xdgDataHome = "${userHome}/.local/share";
    in {
      XDG_DATA_HOME = "${xdgDataHome}";
      XDG_STATE_HOME = "${userHome}/.local/state";
      XDG_CONFIG_HOME = "${userHome}/.config";
      XDG_CACHE_HOME = "${userHome}/.cache";
      GIT_CONFIG_HOME = "${userHome}/.config/git/config";
      NIXOS_CONFIG = "${configRoot}";
      DIRENV_WARN_TIMEOUT = "1h";
      PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
      STARSHIP_LOG = "error";
      EDITOR = "nvim";
      PAGER = "less";
      MANPAGER = "less";
      LESSHISTFILE = "-";
      HISTCONTROL = "ignorespace";
      ENCRYPTION_KEY = "lwLC4GH5UnAYdmHVyfD9UClbMh/saKnRPS+5nILfV2k=";
      POSTGRESQL_PORT = postgresqlPort;
      REDIS_PORT = redisPort;
      REDIS_DB = "0";
    };

    binsh = "${pkgs.dash}/bin/dash";

    systemPackages = with pkgs; [
      # Security and secrets
      age
      sops

      # Web servers
      nginx
      caddy

      # Databases
      redis
      clickhouse
      awscli2
      postgresql

      # System utilities
      dbus
      man-pages
      man-pages-posix
      hwinfo
      file
      lsof
      pciutils
      sysstat
      usbutils
      xz

      # Network tools
      openssh
      openvpn
      aria2
      wireguard-tools
      ngrok
      dnsutils
      ethtool
      iftop
      iotop
      ipcalc
      iperf3
      mtr
      nmap
      socat
      bettercap
      wireshark
      tshark

      # Monitoring
      bottom
      powertop
      upower
      lm_sensors
      ltrace
      strace

      # Compression
      p7zip
      unzip
      zip
      xz
      zstd

      # Command line tools
      dust
      atuin
      expect
      tldr
      procs
      comma
      cowsay
      difftastic
      sudo-rs
      cotp
      as-tree
      eza
      fd
      bat
      ripgrep
      fzf
      jq
      tree
      zoxide
      yazi

      # Editors and shells
      starship
      neovim
      helix
      fish
      dash
      tmux

      # File management
      nnn

      # Development tools
      gh
      git
      git-lfs
      pkg-config
      openssl
      tokei

      # Containerization
      docker-compose
      docker-compose-language-service
      docker-client
      arion
      podman-compose
      cargo-shuttle
      devenv
      nix-direnv

      # Web tools
      httpie
      wget

      # File utilities
      gnupg
      gnused
      gnutar
      pandoc
      wkhtmltopdf

      # Nix tools
      nh
      nix-index
      manix
      nix-output-monitor
      cachix
    ];

    # Store config sources in /etc for systemd service to use
    etc = {
      "nixos-configs/fish".source = ../../home/config/fish;
      "nixos-configs/nvim".source = ../../home/config/nvim;
      "nixos-configs/cargo".source = ../../home/config/cargo;
      "nixos-configs/helix".source = ../../home/config/helix;
      "nixos-configs/nnn".source = ../../home/config/nnn;
      "nixos-configs/tmux".source = ../../home/config/tmux;
      "nixos-configs/lesskey".source = ../../home/config/lesskey;
    };
  };

  powerManagement = {
    enable = true;
  };

  networking = {
    nameservers = [ "8.8.8.8" "1.1.1.1" ];
    extraHosts = ''
      104.18.14.166 api.bitget.com
      104.18.15.166 api.bitget.com
    '';
    firewall = {
      enable = true;
      allowedTCPPorts = [
        80   # HTTP
        443  # HTTPS
        53   # DNS
        22   # SSH
        993  # IMAP
        465  # SMTP
      ];
      allowedUDPPorts = [
        53   # DNS
        67   # DHCP client
        68   # DHCP server
        123  # NTP
        5353 # mDNS
        3478 # STUN
        993  # IMAP
        465  # SMTP
      ];
    };

    hostName = "server";
    wireless.enable = false; # Disable wpa_supplicant to avoid conflict
    networkmanager = {
      dns = "none";
      enable = true;
    };
  };

  nix.settings.auto-optimise-store = true;
  system.stateVersion = "24.05";
}