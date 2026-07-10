# TODO!: move much of this to shared dirs
{ self, config, lib, pkgs, pkgs-ollama, inputs, mylib, user, ... }:
let
  #TODO: `ssh-add ~/.ssh/id_ed25519` as part of the setup
  sshConfigPath = "${config.home.homeDirectory}/.ssh";
  tgPkg = inputs.tg.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  nix.extraOptions = "!include ${config.home.homeDirectory}/s/g/private/sops/";
  # ref: https://www.youtube.com/watch?v=G5f6GC7SnhU
  sops = {
    age.sshKeyPaths = [ "${sshConfigPath}/id_ed25519" ];
    defaultSopsFile = "${self}/secrets/users/v/default.json";
    defaultSopsFormat = "json";
    secrets.telegram_token_main = { mode = "0400"; };
    # openclaw's Telegram channel binds to the *test* bot (@test_my_nonsense_bot) so it doesn't
    # fight tg-server over the main bot's getUpdates long-poll (one consumer per bot token).
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
    secrets.openai_api_key = { mode = "0400"; };
    # NB: sops key is misspelled upstream as `deepsek_key` (single `e`); keep matching the stored name.
    secrets.deepsek_key = { mode = "0400"; };
    secrets.encryption_key = { mode = "0400"; };
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

  # Write secrets to environment.d so ALL systemd user services (openclaw-gateway, tg-server, etc.)
  # inherit them automatically. Generated from sops-decrypted files at `home-manager switch` time.
  home.activation.writeSecretsEnvd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.home.homeDirectory}/.config/environment.d"
    dest="${config.home.homeDirectory}/.config/environment.d/30-secrets.conf"
    {
      echo "OPENAI_API_KEY=$(cat ${config.sops.secrets.openai_api_key.path})"
      echo "OPENAI_KEY=$(cat ${config.sops.secrets.openai_api_key.path})"
      echo "TELEGRAM_MAIN_BOT_TOKEN=$(cat ${config.sops.secrets.telegram_token_main.path})"
      echo "TELEGRAM_BOT_KEY=$(cat ${config.sops.secrets.telegram_token_main.path})"
      # DEEPSEEK_KEY is consumed by the `cld` fish function (home/config/fish/app_aliases/llm.fish)
      # and by the openclaw gateway (DeepSeek is OpenAI-compatible; see configureOpenclaw below).
      echo "DEEPSEEK_KEY=$(cat ${config.sops.secrets.deepsek_key.path})"
      echo "DEEPSEEK_API_KEY=$(cat ${config.sops.secrets.deepsek_key.path})"
      # btc_line's ~/.config/btc_line.nix references these via { env = ... }.
      echo "ALPACA_API_KEY=$(cat ${config.sops.secrets.alpaca_api_pubkey.path})"
      echo "ALPACA_API_SECRET=$(cat ${config.sops.secrets.alpaca_api_secret.path})"
      # Was environment.variables.ENCRYPTION_KEY in os/nixos/shared-services.nix
      # (committed in plaintext, since burned). Session-scoped now.
      echo "ENCRYPTION_KEY=$(cat ${config.sops.secrets.encryption_key.path})"
    } > "$dest"
    chmod 600 "$dest"
    ${pkgs.systemd}/bin/systemctl --user daemon-reload || true
  '';

  # OpenClaw — multi-channel AI gateway, run from the checkout at ~/g/openclaw.
  # Configured for DeepSeek (OpenAI-compatible endpoint) via a non-interactive onboard pass.
  # `onboard --non-interactive` / `config set` / `channels add` are all idempotent and merge into
  # ~/.openclaw/openclaw.json, so this whole block re-runs safely on every `home-manager switch`
  # and fully reproduces config on a clean ~/.openclaw. We materialize secrets from the
  # sops-decrypted files here (openclaw has no env-var expansion in its config), and gate the
  # whole thing on the openclaw checkout actually being present.
  home.activation.configureOpenclaw = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    repo="${config.home.homeDirectory}/g/openclaw"
    keyFile="${config.sops.secrets.deepsek_key.path}"
    tgTokenFile="${config.sops.secrets.telegram_token_test.path}"
    node="${lib.getExe pkgs.nodejs_22}"
    oc() { "$node" "$repo/openclaw.mjs" "$@"; }
    if [ -d "$repo" ] && [ -r "$keyFile" ]; then
      # DeepSeek provider + default model (deepseek-chat -> deepseek-v4 family).
      oc onboard --non-interactive --accept-risk \
        --mode local \
        --auth-choice custom-api-key \
        --custom-provider-id deepseek \
        --custom-base-url "https://api.deepseek.com/v1" \
        --custom-model-id "deepseek-chat" \
        --custom-api-key "$(cat "$keyFile")" \
        --custom-compatibility openai \
        --gateway-port 18789 \
        --gateway-bind loopback \
        --no-install-daemon \
        --skip-channels \
        --skip-skills \
        --skip-ui \
        --skip-health \
        || echo "configureOpenclaw: onboard failed (non-fatal); run 'oclaw' / 'openclaw onboard' manually" >&2

      # The custom-provider onboard defaults the model to a tiny 4096-token window; DeepSeek v4
      # actually serves 128k context / 8k output. Correct it so the agent doesn't over-truncate.
      oc config set 'models.providers.deepseek.models[0].contextWindow' 131072 || true
      oc config set 'models.providers.deepseek.models[0].maxTokens' 8192 || true

      # Telegram channel on the *test* bot (distinct token from tg-server's main bot — see secrets).
      if [ -r "$tgTokenFile" ]; then
        oc plugins enable telegram || true
        oc channels add --channel telegram --token "$(cat "$tgTokenFile")" --name "test_my_nonsense_bot" || true
      else
        echo "configureOpenclaw: $tgTokenFile not readable; skipping telegram channel" >&2
      fi
    else
      echo "configureOpenclaw: $repo missing or $keyFile not readable yet; skipping" >&2
    fi
  '';

  # Fix sops-nix.service to remain active after completion
  # Without this, oneshot services exit immediately and can't satisfy Requires= dependencies
  systemd.user.services.sops-nix = {
    Service = {
      RemainAfterExit = true;
    };
  };

  # Always-on OpenClaw gateway (WebSocket gateway + connected channels + control UI on :18789).
  # Runs the checkout at ~/g/openclaw directly via node — the repo ships a prebuilt dist/, so no
  # build step is needed at start. Config + state live in the persisted ~/.openclaw, written by
  # the configureOpenclaw activation above. Started on login and kept alive across crashes.
  # NB: gated on the openclaw checkout existing so a fresh machine without it doesn't fail to boot
  # into the user session — the ExecStartPre guard exits 0 (skips start) when the repo is absent.
  systemd.user.services.openclaw-gateway = lib.mkIf user.openclaw {
    Unit = {
      Description = "OpenClaw multi-channel AI gateway (DeepSeek)";
      After = [ "network-online.target" "sops-nix.service" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      # Skip cleanly if the checkout isn't there yet (first boot before `git clone`).
      ExecStartPre = "${pkgs.bash}/bin/bash -c '[ -f ${config.home.homeDirectory}/g/openclaw/openclaw.mjs ]'";
      ExecStart = "${lib.getExe pkgs.nodejs_22} ${config.home.homeDirectory}/g/openclaw/openclaw.mjs gateway --port 18789";
      Restart = "on-failure";
      RestartSec = 5;
      # openclaw resolves its own paths under ~/.openclaw by default; be explicit for the service.
      Environment = [ "OPENCLAW_STATE_DIR=${config.home.homeDirectory}/.openclaw" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Ensure tg-server waits for sops-nix secrets to be available
  systemd.user.services.tg-server = {
    Unit = {
      After = lib.mkForce [ "network.target" "sops-nix.service" ];
      StartLimitIntervalSec = 60;
      StartLimitBurst = 10;
    };

    Service = {
      # Wait for the sops-nix secret file to exist before systemd tries to load it
      ExecStartPre = lib.mkBefore "${pkgs.bash}/bin/bash -c 'while [ ! -f ${config.sops.secrets.telegram_token_main.path} ]; do ${pkgs.coreutils}/bin/sleep 0.1; done'";
      RestartSec = 5;
      # Inject OpenAI key so tg-server can do voice transcription
      LoadCredential = lib.mkAfter [ "openai_key:${config.sops.secrets.openai_api_key.path}" ];
      ExecStart = lib.mkForce "/bin/sh -c 'TELEGRAM_API_HASH=\"$(cat %d/tg_api_hash)\" PHONE_NUMBER_FR=\"$(cat %d/tg_phone)\" TELEGRAM_ALERTS_CHANNEL_ID=\"$(cat %d/tg_alerts_channel)\" OPENAI_API_KEY=\"$(cat %d/openai_key)\" ${tgPkg}/bin/tg --token \"$(cat %d/tg_token)\" server'";
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
      "cloudzy_fedora" = {
        hostname = "144.172.114.210";
        user = "root";
      };
      "win_dima_tokyo" = {
        hostname = "38.180.201.212";
        user = "Administrator";
        identitiesOnly = true;
        identityFile = [ "~/.ssh/id_ed25519" ];
        extraOptions = {
          PreferredAuthentications = "publickey,keyboard-interactive,password";
          PubkeyAuthentication = "yes";
          StrictHostKeyChecking = "accept-new";
        };
      };
      # inferno VPS (Tokyo) — main server, runs site/social_networks/server_upkeep
      "inferno_vps_tokyo" = {
        hostname = "176.97.73.24";
        user = "root";
        identitiesOnly = true;
        identityFile = [ "~/.ssh/id_ed25519" ];
        extraOptions = {
          PreferredAuthentications = "publickey,keyboard-interactive,password";
          PubkeyAuthentication = "yes";
          StrictHostKeyChecking = "accept-new";
        };
      };
      # inferno VPS (Singapore) — secondary server, mirrors Tokyo setup
      "inferno_vps_singapore" = {
        hostname = "38.180.74.10";
        user = "root";
        identitiesOnly = true;
        identityFile = [ "~/.ssh/id_ed25519" ];
        extraOptions = {
          PreferredAuthentications = "publickey,keyboard-interactive,password";
          PubkeyAuthentication = "yes";
          StrictHostKeyChecking = "accept-new";
        };
      };
      # rpi5 — home k3s box (site/rea via CF tunnel). LAN-only via mDNS; the box
      # re-probes and reclaims the bare rpi5.local on every deploy (see its
      # avahiReclaim activation script). Off-LAN: use the tailscale name instead.
      "rpi5" = {
        hostname = "rpi5.local";
        user = "admin";
        identitiesOnly = true;
        identityFile = [ "~/.ssh/id_ed25519" ];
        extraOptions = {
          ForwardAgent = "yes"; # git auth on the box uses your forwarded key
          PreferredAuthentications = "publickey,keyboard-interactive,password";
          PubkeyAuthentication = "yes";
          StrictHostKeyChecking = "accept-new";
        };
      };
      # rpi5 over tailscale (native node of the personal tailnet, shared into
      # ev-invest for coworkers). MagicDNS name — survives IP reassignment.
      "rpi5-ts" = {
        hostname = "rpi5.taila74a7d.ts.net";
        user = "admin";
        identitiesOnly = true;
        identityFile = [ "~/.ssh/id_ed25519" ];
        extraOptions = {
          ForwardAgent = "yes";
          PreferredAuthentications = "publickey,keyboard-interactive,password";
          PubkeyAuthentication = "yes";
          StrictHostKeyChecking = "accept-new";
        };
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
				fastfetch # main system info
        libinput
        virt-viewer
        gnome-boxes

        ringboard-wayland

        # repo history interactions
        [
          gitui #DEPRECATE: pretty sure lazygit is just better
          lazygit # tui interface for common git operations
          gource # visualize git history (animates how repo graph grew)
        ]

        # excalidraw
        [
          obsidian # want it for excalidraw interop
          excalidraw_export # svg and png from .excalidraw
        ]

        pkgs-ollama.ollama-cuda # pinned nixpkgs to avoid rebuilds

        ghostty # in case I need inline images

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

        # Trading bots
        [
          metascalp
        ]

        # Windows (via WinApps/Docker VM)
        [
          inputs.winapps.packages.${pkgs.stdenv.hostPlatform.system}.winapps
          inputs.winapps.packages.${pkgs.stdenv.hostPlatform.system}.winapps-launcher
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
        # NB: per-Read malware-reminder was removed upstream as of claude-code 2.1.154, but the
        # patch infra now strips a DIFFERENT annoyance: the always-on AskUserQuestion guidance
        # that nudges Claude to ask clarifying questions (contradicting my "just do the work"
        # CLAUDE.md). See patched-claude-code.nix / strip-claude-reminders.py.
        (import ./patched-claude-code.nix {
          inherit pkgs;
          claude-code = inputs.claude_code_nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
        })
        inputs.codex_nix.packages.${pkgs.stdenv.hostPlatform.system}.default

        libreoffice-still
    
        gnuplot # plot functions for visual exploration (good for ones outside of 2d)

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
        inputs.decant.packages.${pkgs.stdenv.hostPlatform.system}.default

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
