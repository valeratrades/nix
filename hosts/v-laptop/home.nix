# TODO!: move much of this to shared dirs
{ self, config, lib, pkgs, inputs, mylib, user, ... }:
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
    secrets.mail_main_addr = { mode = "0400"; };
    secrets.mail_main_pass = { mode = "0400"; };
    secrets.mail_spam_addr = { mode = "0400"; };
    secrets.mail_spam_pass = { mode = "0400"; };
  };

  tg = {
    enable = true;
    package = inputs.tg.packages.${pkgs.system}.default;
    token = config.sops.secrets.telegram_token_main.path;
  };

  # Fix sops-nix.service to remain active after completion
  # Without this, oneshot services exit immediately and can't satisfy Requires= dependencies
  systemd.user.services.sops-nix = {
    Service = {
      RemainAfterExit = true;
    };
  };

  # Ensure tg-server waits for sops-nix secrets to be available
  systemd.user.services.tg-server = {
    Unit = {
      After = lib.mkForce [ "network.target" "sops-nix.service" ];
      Requires = [ "sops-nix.service" ];
    };

    Service = {
      LoadCredential = "tg_token:${config.sops.secrets.telegram_token_main.path}";
      ExecStart = lib.mkForce ''
        ${pkgs.bash}/bin/bash -c '${
          inputs.tg.packages.${pkgs.system}.default
        }/bin/tg --token "$(${pkgs.coreutils}/bin/cat /run/user/1000/credentials/tg-server.service/tg_token)" server'
      '';
      # Wait for the sops-nix secret file to exist before systemd tries to load it
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'while [ ! -f ${config.sops.secrets.telegram_token_main.path} ]; do ${pkgs.coreutils}/bin/sleep 0.1; done'";
    };
  };

	# is coupled with ssh block in main `configuration.bix`
	programs.ssh = {
		enable = true; #Q: do I need this if `enableDefaultConfig = false`?
		enableDefaultConfig = false;
		
		#startAgent = true; # openssh remembers private keys; `ssh-add` adds a key to the agent
		#enableAskPassword = true;
		#extraConfig = ''
		#	PasswordAuthentication = yes
		#'';
		matchBlocks = {
			"github.com" = {
				hostname = "github.com";
				user = "git";
				identitiesOnly = true;
				identityFile = [ "~/.ssh/id_ed25519" ];
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


        gitui
        lazygit

				# ProtonMail
				#dbg: was bringing `webkitgtk`
				#[
				#	protonmail-export # export my proton emails as `.eml` #DEPRECATE: not sure if I need it, bridge+himalaya could be covering this
				#	protonmail-bridge # bridge to local e-mail client
				#	protonmail-desktop #TODO: replace with himalaya
				#]

        zed-editor-fhs
				zed
				claude-code


				simplescreenrecorder

        #flutterPackages-source.stable // errors

				# ISOs
				[
					ventoy-full-gtk # solution for multiple ISOs on same USB
					woeusb # writing bootable USB, Windows-native solution
					mediawriter # Fedora-approved USB burner
				]

      ]

      ++ [
        # some of my own packages are in shared, not everything is here
        inputs.btc_line.packages.${pkgs.system}.default
        inputs.prettify_log.packages.${pkgs.system}.default
        inputs.distributions.packages.${pkgs.system}.default # ? shared?
        inputs.book_parser.packages.${pkgs.system}.default
        inputs.rm_engine.packages.${pkgs.system}.default
        inputs.bad_apple_rs.packages.${pkgs.system}.default
        inputs.ask_llm.packages.${pkgs.system}.default
        inputs.translate_infrequent.packages.${pkgs.system}.default
        inputs.cargo_sort_derives.packages.${pkgs.system}.default

        #inputs.aggr_orderbook.packages.${pkgs.system}.default
        #inputs.orderbook_3d.packages.${pkgs.system}.default
      ];
    #TODO: himalaya. Problems: (gmail requires oauth2, proton requires redirecting to it (also struggling with it))
    file = {
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
          };
        };
      ".config/todo.toml".source = "${self}/home/config/todo.toml";
    };
  };
}
