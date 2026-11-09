# TODO!: move much of this to shared dirs
{ self, config, lib, pkgs, pkgs-ollama, inputs, mylib, myvars, user, ... }:
let
  #TODO: `ssh-add ~/.ssh/id_ed25519` as part of the setup
  sshConfigPath = "${config.home.homeDirectory}/.ssh";
  tgPkg = inputs.tg.packages.${pkgs.stdenv.hostPlatform.system}.default;
  sopsFile = "${self}/secrets/users/v/default.json";
  sopsTree = removeAttrs (builtins.fromJSON (builtins.readFile sopsFile)) [ "sops" ]; # key names are plaintext in a sops file
  # `<scope>.env.NAME` -> NAME in environment.d, so every systemd user service inherits it
  secretsEnv = lib.concatMapAttrs (scope: v: lib.mapAttrs (name: _: "${scope}/env/${name}") (v.env or { })) sopsTree;
  # a fish `set` of the same name shadows the sops value in every shell
  credentialsFishVars = lib.optionals (!lib.inPureEvalMode) (lib.concatMap
    (l: let m = builtins.match "[[:space:]]*set[[:space:]]+(-[^[:space:]]+[[:space:]]+)*([^-[:space:]][^[:space:]]*).*" l; in lib.optional (m != null) (builtins.elemAt m 1))
    (lib.splitString "\n" (builtins.readFile "${config.home.homeDirectory}/s/g/private/credentials.fish"))); #IMPURE
  secretsEnvCollisions = lib.intersectLists (builtins.attrNames secretsEnv) credentialsFishVars;
  askLlm = inputs.ask_llm.packages.${pkgs.stdenv.hostPlatform.system}.default;
  # by email; the session starts on the first with room left, a hit limit moves on to the next such. Others are switched to by hand only
  claudeAutoAccounts = [ "admin@evinvest.ltd" "v79166789533@gmail.com" ];
in {
  nix.extraOptions = "!include ${config.home.homeDirectory}/s/g/private/sops/";
  # ref: https://www.youtube.com/watch?v=G5f6GC7SnhU
  sops = {
    age.sshKeyPaths = [ "${sshConfigPath}/id_ed25519" ];
    defaultSopsFile = sopsFile;
    defaultSopsFormat = "json";
    secrets = let leaves = prefix: lib.concatMapAttrs (k: v: if builtins.isAttrs v then leaves "${prefix}${k}/" v else { "${prefix}${k}" = { }; }); in leaves "" sopsTree;
  };

  tg = {
    enable = true;
    package = import ../../home/config/fish/with_fish_init.nix pkgs { pkg = inputs.tg.packages.${pkgs.stdenv.hostPlatform.system}.default; cmd = "tg init fish"; };
    apiHash = config.sops.secrets."social-networks/telegram_api_hash".path;
    phone = config.sops.secrets."social-networks/telegram_phone".path;
    alertsChannel = config.sops.secrets."social-networks/telegram_alerts_channel".path;
  };

  systemd.user.services.keepassxc = {
    Unit = {
      Description = "KeePassXC with the main database unlocked from sops";
      After = [ "sway-session.target" "sops-nix.service" ];
      Wants = [ "sops-nix.service" ]; # Requires would stop it on every switch's sops-nix restart
      PartOf = [ "sway-session.target" ];
    };
    Install.WantedBy = [ "sway-session.target" ];
    Service = {
      ExecStart = "${config.programs.keepassxc.package}/bin/keepassxc --minimized";
      # D-Bus rather than --pw-stdin: the latter segfaults in MainWindow::bringToFront (2.7.12)
      ExecStartPost = toString (pkgs.writeShellScript "keepassxc-unlock" ''
        for _ in $(seq 50); do ${pkgs.systemd}/bin/busctl --user status org.keepassxc.KeePassXC.MainWindow >/dev/null 2>&1 && break; sleep 0.2; done
        set -e
        ${pkgs.systemd}/bin/busctl --user call org.keepassxc.KeePassXC.MainWindow /keepassxc org.keepassxc.KeePassXC.MainWindow \
          openDatabase ss ${config.home.homeDirectory}/s/g/private/keepassxc/main.kdbx "$(cat ${config.sops.secrets."other/keepassxc_password".path})"
      '');
    };
  };

  systemd.user.services.claude-first-account = {
    Unit = {
      Description = "Point claude's current account at the first of the auto-rotated ones with room left";
      X-SwitchMethod = "keep-old"; # a rebuild mid-session must not move every claude back
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = toString (pkgs.writeShellScript "claude-first-account" ''
        set -euo pipefail
        if [ -e "$HOME/.local/state/claude-auto-rotate-off" ]; then
          echo "auto-rotation is off (cl auto off); current stays where it is"
          exit 0
        fi
        name=$(${askLlm}/bin/ask_llm dev claude-account list --json | ${pkgs.jq}/bin/jq -nr --argjson auto ${lib.escapeShellArg (builtins.toJSON claudeAutoAccounts)} \
          '[inputs] as $all | first($auto[] as $e | $all[] | select(.email == $e and (.disabled | not)) | .name) // empty')
        if [ -z "$name" ]; then
          echo "every auto-rotated account is spent until its reset; current stays where it is"
          exit 0
        fi
        exec ${askLlm}/bin/ask_llm dev claude-account rotate "$name"
      '');
    };
  };

  wallpaper-carousel = {
    enable = false; #Q: not sold on having this run hourly. Interferes with any manual wallpaper setting
    package = inputs.wallpaper_carousel.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

  btc_line = {
    enable = true;
    package = inputs.btc_line.packages.${pkgs.stdenv.hostPlatform.system}.default;
    alpacaKey = config.sops.secrets."trading/env/ALPACA_API_KEY".path;
    alpacaSecret = config.sops.secrets."trading/env/ALPACA_API_SECRET".path;
  };

  assertions = map (name: { assertion = builtins.match "[A-Z_][A-Z0-9_]*" name != null; message = "sops env key `${name}` is not an env var name"; }) (builtins.attrNames secretsEnv);
  warnings = map (v: "${v}: set both in sops (secrets/users/v/default.json) and in credentials.fish, which shadows it in fish") secretsEnvCollisions;

  # upstream's restarts the old unit, which reloadSystemd only later swaps, so it decrypts the previous manifest
  home.activation.sops-nix = lib.mkForce ''
    if [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
      ${pkgs.coreutils}/bin/env ${lib.escapeShellArgs (lib.mapAttrsToList (n: v: "${n}=${v}") config.sops.environment)} ${lib.head config.systemd.user.services.sops-nix.Service.ExecStart}
    else
      echo "sops-nix: no user session, its unit decrypts once one starts"
    fi
  '';

  home.activation.writeSecretsEnvd = let paths = lib.mapAttrs (_: key: config.sops.secrets.${key}.path) secretsEnv; in lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] ''
    if [ -n "''${XDG_RUNTIME_DIR:-}" ]; then # without a session nothing is decrypted, and the last switch's file stands
      cat ${lib.escapeShellArgs (lib.attrValues paths)} >/dev/null
      mkdir -p "${config.home.homeDirectory}/.config/environment.d"
      dest="${config.home.homeDirectory}/.config/environment.d/30-secrets.conf"
      {
        ${lib.concatStrings (lib.mapAttrsToList (env: path: ''
          echo "${env}=$(cat ${path})"
        '') paths)}
      } > "$dest"
      chmod 600 "$dest"
      ${pkgs.systemd}/bin/systemctl --user daemon-reload
    fi
  '';

  # `@local/v-utils:0.0.0` = live checkout, like a cargo path override; typst wants an exact version matching the manifest, hence our own toml
  home.activation.typUtilsLocal = let
    manifest = (pkgs.formats.toml { }).generate "typst.toml" {
      package = { name = "v-utils"; version = "0.0.0"; entrypoint = "src/lib.typ"; authors = [ "Valera" ]; license = "MIT"; description = "Local HEAD of ~/s/typ/typ_utils"; };
    };
  in lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    repo="${config.home.homeDirectory}/s/typ/typ_utils"
    pkg="${config.home.homeDirectory}/.local/share/typst/packages/local/v-utils/0.0.0"
    mkdir -p "$pkg"
    case "$(realpath "$pkg")/" in "$(realpath -m "$repo")"/*) echo "typUtilsLocal: $pkg resolves into $repo; refusing to write the manifest over the checkout's" >&2; exit 1;; esac
    [ -d "$repo" ] || echo "typUtilsLocal: $repo missing; @local/v-utils:0.0.0 dangles until it's cloned (github.com/valeratrades/typ_utils)" >&2
    ln -sfn ${manifest} "$pkg/typst.toml"
    ln -sfn "$repo" "$pkg/src" # -n: replace an existing link, never descend into it (would plant a loop inside the checkout)
  '';

  # OpenClaw — multi-channel AI gateway, run from the checkout at ~/g/openclaw.
  # Engine is GPT-5.6 Luna, reached through the local litellm proxy below rather than openclaw's
  # native `openai` provider: openclaw routes that one through the codex app-server runtime, whose
  # @openai/codex-linux-x64 binary is not installed in the checkout. litellm is already running for
  # `clc`, speaks plain OpenAI-compatible HTTP, and keeps both consumers on one funnel.
  # `onboard --non-interactive` / `config patch` / `channels add` are all idempotent and merge into
  # ~/.openclaw/openclaw.json, so this whole block re-runs safely on every `home-manager switch`
  # and fully reproduces config on a clean ~/.openclaw. We materialize secrets from the
  # sops-decrypted files here (openclaw has no env-var expansion in its config), and gate the
  # whole thing on the openclaw checkout actually being present.
  home.activation.configureOpenclaw = let
    ocCfg = {
      provider = "litellm";
      baseUrl = "http://127.0.0.1:${toString myvars.ports.litellm}";
      model = "luna";
      port = toString myvars.ports.openclawGateway;
    };
    # Mirrors the openai plugin's own catalog entry for gpt-5.6-luna (extensions/openai/
    # openclaw.plugin.json) -- litellm serves the model but reports no metadata for it, so the
    # window, output cap and price have to be stated here or the agent over-truncates and
    # mis-accounts. `local`: the proxy binds loopback with no master_key, so any token passes.
    ocModel = builtins.toJSON {
      models.providers.litellm = {
        baseUrl = ocCfg.baseUrl;
        apiKey = "local";
        api = "openai-completions";
        models = [{
          id = ocCfg.model;
          name = "GPT-5.6 Luna (litellm)";
          api = "openai-completions";
          reasoning = true;
          input = [ "text" "image" ];
          contextWindow = 372000;
          maxTokens = 128000;
          cost = { input = 1; output = 6; cacheRead = 0.1; cacheWrite = 1.25; };
        }];
      };
      agents.defaults.model.primary = "${ocCfg.provider}/${ocCfg.model}";
      # Routed from Telegram, so the agent needs the message tool for reply/thread-reply/attachment
      # actions. alsoAllow rather than allow: additive on top of the profile, so it stays auditable.
      tools.alsoAllow = [ "group:messaging" ];
    };
    cfgHash = builtins.hashString "sha256" ocModel;
  in lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] ''
    repo="${config.home.homeDirectory}/g/openclaw"
    tgTokenFile="${config.sops.secrets."social-networks/telegram_token_test".path}" # test bot: the main one is tg-server's getUpdates long-poll, one consumer per bot token
    node="${lib.getExe pkgs.nodejs_22}"
    oc() { "$node" "$repo/openclaw.mjs" "$@"; }
    # Each oc call spawns node (~7s), 5 calls => ~35-62s. This block is idempotent but only needs
    # to actually run when config inputs change. Stamp over the nix config + secret contents and
    # skip the whole dance on unchanged boots/switches.
    stamp="${config.home.homeDirectory}/.openclaw/.hm-config-stamp"
    want="$( { printf '%s' '${cfgHash}'; cat "$tgTokenFile" 2>/dev/null; } | sha256sum | cut -d' ' -f1 )"
    if [ -r "$stamp" ] && [ "$(cat "$stamp")" = "$want" ]; then
      echo "configureOpenclaw: config unchanged, skipping"
    elif [ -d "$repo" ]; then
      # Gateway/workspace/mode only. `--auth-choice skip`: onboard's custom-provider flags refuse to
      # overwrite an existing provider id and silently mint `litellm-2`, `litellm-3`, ... on every
      # re-run, so the model side is left entirely to the patch below.
      oc onboard --non-interactive --accept-risk \
        --mode local \
        --auth-choice skip \
        --gateway-port ${ocCfg.port} \
        --gateway-bind loopback \
        --no-install-daemon \
        --skip-channels \
        --skip-skills \
        --skip-ui \
        --skip-health \
        || echo "configureOpenclaw: onboard failed (non-fatal); run 'oclaw' / 'openclaw onboard' manually" >&2

      # --replace-path: providers become exactly what nix declares, so a provider dropped here (or
      # an accidental `litellm-N`) disappears instead of lingering as a silent failover.
      printf '%s' ${lib.escapeShellArg ocModel} | oc config patch --stdin --replace-path models.providers \
        || echo "configureOpenclaw: model patch failed; openclaw is left on whatever onboard wrote" >&2

      # Telegram channel on the *test* bot (distinct token from tg-server's main bot — see secrets).
      if [ -r "$tgTokenFile" ]; then
        oc plugins enable telegram || true
        oc channels add --channel telegram --token "$(cat "$tgTokenFile")" --name "test_my_nonsense_bot" || true
      else
        echo "configureOpenclaw: $tgTokenFile not readable; skipping telegram channel" >&2
      fi
      mkdir -p "$(dirname "$stamp")" && printf '%s' "$want" > "$stamp"
    else
      echo "configureOpenclaw: $repo missing; skipping" >&2
    fi
  '';

  # Fix sops-nix.service to remain active after completion
  # Without this, oneshot services exit immediately and can't satisfy Requires= dependencies
  systemd.user.services.sops-nix = {
    Service = {
      RemainAfterExit = true;
    };
  };

  # Always-on OpenClaw gateway (WebSocket gateway + connected channels + control UI; port in vars/ports.nix).
  # Runs the checkout at ~/g/openclaw directly via node, from its locally-built dist/ (untracked;
  # produced by `openclaw-rebuild`). Config + state live in the persisted ~/.openclaw, written by
  # the configureOpenclaw activation above. Started on login and kept alive across crashes.
  # The preflight refuses to start on a dist/ built from a different commit than the checkout's
  # HEAD: a stale dist against a moved tree crash-loops on plugin/config validation (2026-07-11
  # outage), so fail immediately with an actionable message instead.
  systemd.user.services.openclaw-gateway = lib.mkIf user.openclaw {
    Unit = {
      Description = "OpenClaw multi-channel AI gateway (GPT-5.6 Luna via litellm)";
      # litellm now carries the engine, not just `clc` -- without it every agent turn 502s.
      After = [ "network-online.target" "sops-nix.service" "litellm.service" ];
      Wants = [ "network-online.target" "litellm.service" ];
      # Crash-looping forever helps nobody: after the burst, give up and page via telegram.
      # Window sized for the backoff below: 10 restarts' delays sum to ~10min, leaving slack for run time.
      StartLimitIntervalSec = 1800;
      StartLimitBurst = 10;
      OnFailure = [ "openclaw-gateway-alert.service" ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = "${pkgs.writeShellScript "openclaw-preflight" ''
        repo="${config.home.homeDirectory}/g/openclaw"
        [ -f "$repo/openclaw.mjs" ] || { echo "openclaw checkout missing at $repo" >&2; exit 1; }
        [ -f "$repo/dist/build-info.json" ] || { echo "no dist/ at $repo — run openclaw-rebuild" >&2; exit 1; }
        built=$(${pkgs.jq}/bin/jq -r .commit "$repo/dist/build-info.json")
        head=$(${pkgs.git}/bin/git -C "$repo" rev-parse HEAD)
        if [ "$built" != "$head" ]; then
          echo "dist/ built from $built but checkout is at $head — run openclaw-rebuild" >&2
          exit 1
        fi
      ''}";
      ExecStart = "${lib.getExe pkgs.nodejs_22} ${config.home.homeDirectory}/g/openclaw/openclaw.mjs gateway --port ${toString myvars.ports.openclawGateway}";
      Restart = "on-failure";
      # Without `direct` the unit enters failed between every auto-restart, so OnFailure= pages once
      # per attempt -- 21 identical telegram messages per boot (2026-09-03). Fire only at the limit.
      RestartMode = "direct";
      RestartSec = 5;
      RestartSteps = 10;
      RestartMaxDelaySec = 300;
      # openclaw resolves its own paths under ~/.openclaw by default; be explicit for the service.
      Environment = [ "OPENCLAW_STATE_DIR=${config.home.homeDirectory}/.openclaw" ];
      ExecStartPost = "${pkgs.coreutils}/bin/rm -f %t/openclaw-gateway-alerted"; # re-arm the page once preflight passes
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.openclaw-gateway-alert = lib.mkIf user.openclaw {
    Unit.Description = "Telegram alert when openclaw-gateway exhausts its restart budget";
    Service = {
      Type = "oneshot";
      # Test-bot token, not main: telegram_token_main is currently revoked (401 on getMe,
      # 2026-07-11), and Bot API sends don't conflict with the gateway's getUpdates poll anyway —
      # least of all when this fires, i.e. when the gateway is down.
      # Reboots and hm switches re-arm the start limit; page once per login session (%t is tmpfs).
      ExecStart = "${pkgs.writeShellScript "openclaw-alert" ''
        [ -e "$XDG_RUNTIME_DIR/openclaw-gateway-alerted" ] && exit 0
        token=$(cat ${config.sops.secrets."social-networks/telegram_token_test".path})
        chat=$(cat ${config.sops.secrets."social-networks/telegram_alerts_channel".path})
        ${pkgs.curl}/bin/curl -fsS -m 10 "https://api.telegram.org/bot$token/sendMessage" \
          -d chat_id="$chat" \
          --data-urlencode text="openclaw-gateway is DOWN on ${user.desktopHostName} (start limit hit). If ~/g/openclaw HEAD moved without a rebuild, run: openclaw-rebuild. Logs: journalctl --user -u openclaw-gateway"
        touch "$XDG_RUNTIME_DIR/openclaw-gateway-alerted"
      ''}";
    };
  };


  # OpenAI-compatible router in front of Claude Code (`clc` in llm.fish talks to it as if it were
  # the Anthropic API). Kept a *user* service: the OpenAI key only exists sops-decrypted per-user.
  systemd.user.services.litellm = {
    Unit = {
      Description = "litellm proxy (OpenAI <- Anthropic API shim)";
      After = [ "network-online.target" "sops-nix.service" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      LoadCredential = [ "openai_key:${config.sops.secrets."ai/env/OPENAI_API_KEY".path}" ];
      ExecStart = "/bin/sh -c 'OPENAI_API_KEY=\"$(cat %d/openai_key)\" ${lib.getExe pkgs.litellm} --config ${config.home.homeDirectory}/.config/litellm/openai.yaml --port ${toString myvars.ports.litellm}'";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # OneDrive as a plain directory. Contents are fetched on open and uploaded on close
  # (vfs-cache-mode full), so writes land in the cloud without an explicit sync step.
  # Auth is NOT declared here: OneDrive rotates the OAuth refresh token and rclone writes
  # it back to ~/.config/rclone/rclone.conf, so nix owning that file would restore a dead
  # token on every switch. One-time setup: `rclone config` -> new remote named `onedrive`.
  systemd.user.services.onedrive-mount = {
    Unit = {
      Description = "OneDrive at ~/Documents/Cloud/onedrive (rclone FUSE)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "notify";
      Environment = [ "PATH=/run/wrappers/bin" ]; # fusermount3
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/Documents/Cloud/onedrive";
      ExecStart = lib.concatStringsSep " " [
        "${lib.getExe pkgs.rclone} mount onedrive: %h/Documents/Cloud/onedrive"
        "--vfs-cache-mode full --cache-dir %C/rclone"
        "--dir-cache-time 5000h --poll-interval 15s" # server-side change polling keeps the long dir cache honest
        "--umask 077"
      ];
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # `accounting` in fish
  systemd.user.services.accounting = {
    Unit.Description = "Books: Grafana over the hledger journal, with rate/usage pulls";
    Service = {
      Type = "simple";
      ExecStartPre = "${pkgs.networkmanager}/bin/nm-online -q -t 86400"; # user manager has no network-online.target
      ExecStart = "/run/current-system/sw/bin/nix run %h/s/ev/_service_arb/accounting";
      TimeoutStartSec = "infinity";
      Restart = "on-failure";
      RestartSec = 30;
    };
    Install.WantedBy = [ "default.target" ];
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
      ExecStartPre = lib.mkBefore "${pkgs.bash}/bin/bash -c 'while [ ! -f ${config.sops.secrets."social-networks/telegram_api_hash".path} ]; do ${pkgs.coreutils}/bin/sleep 0.1; done'";
      RestartSec = 5;
      # Inject OpenAI key so tg-server can do voice transcription
      LoadCredential = lib.mkAfter [ "openai_key:${config.sops.secrets."ai/env/OPENAI_API_KEY".path}" ];
      ExecStart = lib.mkForce "/bin/sh -c 'TELEGRAM_API_HASH=\"$(cat %d/tg_api_hash)\" PHONE_NUMBER_FR=\"$(cat %d/tg_phone)\" TELEGRAM_ALERTS_CHANNEL_ID=\"$(cat %d/tg_alerts_channel)\" OPENAI_API_KEY=\"$(cat %d/openai_key)\" ${tgPkg}/bin/tg server'";
    };
  };

  xdg.desktopEntries.coinpoker = {
    name = "CoinPoker";
    exec = "coinpoker";
    icon = "${config.home.homeDirectory}/.wine-coinpoker/drive_c/CoinPoker/resources/assets/cp-icon.png";
    terminal = false;
    settings.StartupWMClass = "coinpoker.exe";
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
        (pkgs.writeShellScriptBin "openclaw" ''
          exec ${lib.getExe pkgs.nodejs_22} "$HOME/g/openclaw/openclaw.mjs" "$@"
        '')

        # The full update dance for the openclaw checkout — anything less than all of these steps
        # after moving HEAD leaves the gateway broken (stale dist) or crash-looping (schema drift).
        (pkgs.writeShellScriptBin "openclaw-rebuild" ''
          set -euo pipefail
          cd "$HOME/g/openclaw"
          export CI=true COREPACK_ENABLE_DOWNLOAD_PROMPT=0
          export PATH="${pkgs.nodejs_22}/bin:$PATH"
          corepack pnpm install --frozen-lockfile
          corepack pnpm build
          node openclaw.mjs doctor --fix
          systemctl --user restart openclaw-gateway
          sleep 20
          node openclaw.mjs channels status --probe
        '')

        chromium
        rclone # cloud remotes; drives the onedrive mount below
        #en-croissant # chess analysis GUI #dbg: may be bringing in `webkitgtk`
        ncspot
				fastfetch # main system info
        libinput
        virt-viewer
        gnome-boxes
        gnome-sound-recorder

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

        freeplane # mind maps

        pkgs-ollama.ollama-cuda # pinned nixpkgs to avoid rebuilds

        ghostty # in case I need inline images

        powershell # for shit and giggles

        # Windows (via Wine)
        [
          sierra-chart
          tiger-trade
          coinpoker
        ]

        # SIP (through Proton)
        [
          microsip
          baresip
          ringo
        ]

        # Trading bots
        [
          metascalp
        ]

        [
          graphify
        ]

        gologin # antidetect browser

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
          ask_llm = askLlm;
          autoAccounts = claudeAutoAccounts;
        })
        inputs.codex_nix.packages.${pkgs.stdenv.hostPlatform.system}.default

        libreoffice-still
        whatsie # C++ whatsapp client

        #vscode # bugged for me; `code` -> codium instead
        (pkgs.writeShellScriptBin "code" ''exec ${lib.getExe pkgs.vscodium} "$@"'')
    
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
        #(import ../../home/config/fish/with_fish_init.nix pkgs { pkg = inputs.discretionary_engine.packages.${pkgs.stdenv.hostPlatform.system}.default; cmd = "discretionary_engine init fish"; })
        inputs.bad_apple_rs.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.ask_llm.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.translate_infrequent.packages.${pkgs.stdenv.hostPlatform.system}.default
        (inputs.v_flakes.rs.sort_derives pkgs.stdenv.hostPlatform.system) # patched: qualified derives can sort last
        inputs.btc_line.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.scripters.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.bourso-api.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.wallpaper_carousel.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.decant.packages.${pkgs.stdenv.hostPlatform.system}.default

        #inputs.aggr_orderbook.packages.${pkgs.stdenv.hostPlatform.system}.default
        #inputs.orderbook_3d.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    file = {
      #".local/share/fonts/FillLevels.ttf".source = config.lib.file.mkOutOfStoreSymlink "/home/v/nix/home/fs/fonts/FillLevels.ttf"; 
    };
  };

  accounts.email.accounts = let
    gmail = { address, passSecret }: {
      inherit address;
      flavor = "gmail.com";
      realName = "Valera";
      passwordCommand = "cat ${config.sops.secrets.${passSecret}.path}"; # app password, - gmail rejects account passwords over IMAP/SMTP
      folders = {
        inbox = "INBOX";
        sent = "[Gmail]/Sent Mail";
        drafts = "[Gmail]/Drafts";
        trash = "[Gmail]/Trash";
      };
      neomutt = {
        enable = true;
        mailboxType = "imap";
        extraConfig = "unset record"; # gmail files SMTP-sent mail into Sent itself
      };
      himalaya.enable = true;
    };
  in {
    valeratrades = gmail { address = "valeratrades@gmail.com"; passSecret = "other/mail_main_pass"; } // { primary = true; };
    v79166789533 = gmail { address = "v79166789533@gmail.com"; passSecret = "other/mail_spam_pass"; };
    "1cryptoicos" = gmail { address = "1cryptoicos@gmail.com"; passSecret = "other/mail_test_pass"; };
  };
  programs.neomutt = {
    enable = true;
    sidebar.enable = true;
  };
  programs.himalaya.enable = true;
}
