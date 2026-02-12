# TODO!: move much of this to shared dirs
{ self, config, lib, pkgs, pkgs-ollama, inputs, mylib, user, ... }:
let
  #TODO: `ssh-add ~/.ssh/id_ed25519` as part of the setup
  sshConfigPath = "${config.home.homeDirectory}/.ssh";
in {
  nix.extraOptions = "!include ${config.home.homeDirectory}/s/g/private/sops/";
  # ref: https://www.youtube.com/watch?v=G5f6GC7SnhU
  sops = {
    age.sshKeyPaths = [ "${sshConfigPath}/id_ed25519" ];
    defaultSopsFile = "${self}/secrets/users/v/default.json";
    defaultSopsFormat = "json";
    secrets.telegram_token_main = { mode = "0400"; };
    secrets.telegram_token_test = { mode = "0400"; };
    secrets.telegram_api_hash = { mode = "0400"; };
    secrets.telegram_phone = { mode = "0400"; };
    secrets.telegram_alerts_channel = { mode = "0400"; };
    secrets.mail_main_addr = { mode = "0400"; };
    secrets.mail_main_pass = { mode = "0400"; };
    secrets.mail_spam_addr = { mode = "0400"; };
    secrets.mail_spam_pass = { mode = "0400"; };
    secrets.alpaca_api_pubkey = { mode = "0400"; };
    secrets.alpaca_api_secret = { mode = "0400"; };
  };

  tg = {
    enable = true;
    package = inputs.tg.packages.${pkgs.stdenv.hostPlatform.system}.default;
    token = config.sops.secrets.telegram_token_main.path;
    apiHash = config.sops.secrets.telegram_api_hash.path;
    phone = config.sops.secrets.telegram_phone.path;
    alertsChannel = config.sops.secrets.telegram_alerts_channel.path;
  };

  wallpaper-carousel = {
    enable = false; #Q: not sold on having this run hourly. Interferes with any manual wallpaper setting
    package = inputs.wallpaper_carousel.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

  btc_line = {
    enable = true;
    package = inputs.btc_line.packages.${pkgs.stdenv.hostPlatform.system}.default;
    alpacaKey = config.sops.secrets.alpaca_api_pubkey.path;
    alpacaSecret = config.sops.secrets.alpaca_api_secret.path;
  };

  # Fix sops-nix.service to remain active after completion
  # Without this, oneshot services exit immediately and can't satisfy Requires= dependencies
  systemd.user.services.sops-nix = {
    Service = {
      RemainAfterExit = true;
    };
  };

  #TODO!!!!!!!: \\
  #dbg: \
  #systemd.user.services.watch-monitors = {
  #  Service = {
  #    ExecStart = lib.mkForce ''
  #      ${pkgs.bash}/bin/bash -c '${
  #        inputs.todo.packages.${pkgs.stdenv.hostPlatform.system}.default
  #      }/bin/todo watch-monitors'
  #    '';
  #  };
  #};

  # Ensure tg-server waits for sops-nix secrets to be available
  systemd.user.services.tg-server = {
    Unit = {
      After = lib.mkForce [ "network.target" "sops-nix.service" ];
      Requires = [ "sops-nix.service" ];
      StartLimitIntervalSec = 60;
      StartLimitBurst = 10;
    };

    Service = {
      # Wait for the sops-nix secret file to exist before systemd tries to load it
      ExecStartPre = lib.mkBefore "${pkgs.bash}/bin/bash -c 'while [ ! -f ${config.sops.secrets.telegram_token_main.path} ]; do ${pkgs.coreutils}/bin/sleep 0.1; done'";
      RestartSec = 5;
    };
  };

  fonts.fontconfig.enable = true;

	# is coupled with ssh block in main `configuration.bix`
	programs.ssh = {
		enable = true; #Q: do I need this if `enableDefaultConfig = false`?
		enableDefaultConfig = false;
		
		#startAgent = true; # openssh remembers private keys; `ssh-add` adds a key to the agent
		#enableAskPassword = true;
		#extraConfig = ''
		#	PasswordAuthentication = yes
		#'';

    # # Good Practices
    # generally want:
    # - `identitiesOnly = true`: don't try other keys outside of the `identityFile` specified
		matchBlocks = {
      # password of connected hosts:
      # p-laptop: `Mija1234!`, - can just `ssh p@p-laptop.taila74a7d.ts.net` if tailscale's ssh is misbehaving
			"*.ts.net" = {
				extraOptions = {
					StrictHostKeyChecking = "no";
					UserKnownHostsFile = "/dev/null";
				};
			};
			"github.com" = {
				hostname = "github.com";
				user = "git";
				identitiesOnly = true;
				identityFile = [ "~/.ssh/id_ed25519" ];
			};
      "cloudzy_ubuntu" = {
        hostname = "45.59.119.236";
        user = "root";
      };
      "p-laptop" = {
        hostname = "p-laptop";
        user = "p";
				identitiesOnly = true;
				identityFile = [ "~/.ssh/id_ed25519" ];
				extraOptions = {
					PreferredAuthentications = "publickey,keyboard-interactive,password";
					PubkeyAuthentication = "yes";
					StrictHostKeyChecking = "accept-new";
				};
      };
			"vincent" = {
				hostname = "192.168.5.204";
				user = "nixos";
				identitiesOnly = true;
				identityFile = [ "~/.ssh/id_ed25519" ];
				extraOptions = {
					PreferredAuthentications = "publickey,keyboard-interactive,password";
					PubkeyAuthentication = "yes";
					StrictHostKeyChecking = "accept-new";
          WarnWeakCrypto = "no"; # silences https://www.openssh.org/pq.html
				};
			};
			"tima" = {
				hostname = "100.103.90.12";
				user = "t"; #Q: should I make shortcuts for `root@` ?
				identitiesOnly = true;
				identityFile = [ "~/.ssh/id_ed25519" ];
				extraOptions = {
					PreferredAuthentications = "publickey,keyboard-interactive,password";
					PubkeyAuthentication = "yes";
					StrictHostKeyChecking = "accept-new";
				};
			};
			"masha" = {
				hostname = "100.107.132.25";
				user = "m"; #Q: should I make shortcuts for `root@` ?
				identitiesOnly = true;
				identityFile = [ "~/.ssh/id_ed25519" ];
				extraOptions = {
					PreferredAuthentications = "publickey,keyboard-interactive,password";
					PubkeyAuthentication = "yes";
					StrictHostKeyChecking = "accept-new";
				};
			};
		};
	};

  home = {
    packages = with pkgs;
      builtins.trace "DEBUG: sourcing Valera-specific home.nix"
      lib.lists.flatten [
        chromium
        #en-croissant # chess analysis GUI #dbg: may be bringing in `webkitgtk`
        ncspot
				neofetch # main system info
        libinput
        virt-viewer

        ringboard-wayland

        gitui
        lazygit

        pkgs-ollama.ollama-cuda # pinned nixpkgs to avoid rebuilds

        powershell # for shit and giggles

        # for my laptop's hardware
        [
          lenovo-legion
        ]

        # Windows (via Wine)
        [
          sierra-chart
          tiger-trade
        ]

        # vpn
        [
          mullvad # incredibly minimalistic. TODO: switch to it
          #dbg: was bringing `webkitgtk`
          #	protonmail-export # export my proton emails as `.eml` #DEPRECATE: not sure if I need it, bridge+himalaya could be covering this
          #	protonmail-bridge # bridge to local e-mail client
          #	protonmail-desktop #TODO: replace with himalaya
        ]

        zed-editor-fhs
				zed
				#claude-code #DEPRECATE: once sure that https://github.com/sadjow/claude-code-nix is the way to go
        inputs.claude_code_nix.packages.${pkgs.stdenv.hostPlatform.system}.default

        libreoffice-still

        ols
        magic-wormhole # transfer files easily between computers

				simplescreenrecorder

        yt-dlp # cli for downloading stuff from yt

        #flutterPackages-source.stable // errors

				# ISOs
				[
					ventoy-full-gtk # solution for multiple ISOs on same USB
					woeusb # writing bootable USB, Windows-native solution
					mediawriter # Fedora-approved USB burner
				]

				# Browsers
				[
					tor-browser
				]
      ]

      ++ [
        # some of my own packages are in shared, not everything is here
        inputs.snapshot_fonts.packages.${pkgs.stdenv.hostPlatform.system}.default
      ]
      # Optional private packages from local paths (won't fail if path doesn't exist)
      # Uses git+file:// to respect .gitignore (avoids copying massive ignored dirs like target/, .venv/, etc.)
      ++ (let
        tryLocalFlake = { path, submodules ? false }:
          if builtins.pathExists (path + "/flake.nix") && builtins.pathExists (path + "/.gitignore")
            then let
              flake = builtins.getFlake "git+file://${path}${if submodules then "?submodules=1" else ""}";
              pkg = flake.packages.${pkgs.stdenv.hostPlatform.system}.default or null;
            in if pkg != null then [ pkg ] else []
          else builtins.trace "WARNING: optional package not found at ${path}" [];
      in lib.flatten [
          #(tryLocalFlake { path = "/home/v/s/other/uni_headless"; }) #dbg: rebuilds from 0 every time, so problematic
          #(tryLocalFlake { path = "/home/v/s/todo"; })
          #(tryLocalFlake { path = "/home/v/s/discretionary_engine"; })
        ]) ++ [
        inputs.prettify_log.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.distributions.packages.${pkgs.stdenv.hostPlatform.system}.default # ? shared?
        inputs.book_parser.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.discretionary_engine.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.bad_apple_rs.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.ask_llm.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.translate_infrequent.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.cargo_sort_derives.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.btc_line.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.wallpaper_carousel.packages.${pkgs.stdenv.hostPlatform.system}.default

        #inputs.aggr_orderbook.packages.${pkgs.stdenv.hostPlatform.system}.default
        #inputs.orderbook_3d.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    #TODO: himalaya. Problems: (gmail requires oauth2, proton requires redirecting to it (also struggling with it))
    file = {
      #".local/share/fonts/FillLevels.ttf".source = config.lib.file.mkOutOfStoreSymlink "/home/v/nix/home/fs/fonts/FillLevels.ttf"; 
      ".config/himalaya/config.toml".source =
        (pkgs.formats.toml { }).generate "" {
          accounts.master = {
            default = true;
            email = "valeratrades@gmail.com";
            display-name = "valeratrades";
            downloads-dir = "/home/v/Downloads";
            backend.type = "imap";
            backend.host = "imap.gmail.com";
            backend.port = 993;
            backend.login = "valeratrades@gmail.com";
            backend.encryption.type = "tls";
            backend.auth.type = "password";
            backend.auth.command =
              "cat ${config.sops.secrets.mail_main_pass.path}";
            message.send.backend.type = "smtp";
            message.send.backend.host = "smtp.gmail.com";
            message.send.backend.port = 465;
            message.send.backend.login = "valeratrades@gmail.com";
            message.send.backend.encryption.type = "tls";
            message.send.backend.auth.type = "password";
            message.send.backend.auth.command =
              "cat ${config.sops.secrets.mail_main_pass.path}";
            folder.aliases.sent = "[Gmail]/Sent Mail";
            folder.aliases.drafts = "[Gmail]/Drafts";
            folder.aliases.trash = "[Gmail]/Trash";
          };
        };
    };
  };
}
