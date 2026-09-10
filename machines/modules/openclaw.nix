# OpenClaw gateway, spliced into the rpi5 nixosSystem via `extraModules` (outputs/default.nix).
# Lives here rather than in the hosts/rpi5 submodule so the org repo never references anything
# personal. Engine is GPT-5.6 Luna straight off api.openai.com through openclaw's native
# `openai-responses` transport — the desktop's litellm hop existed to reach the Responses API from
# a chat/completions client, which is exactly what this transport does natively.
{ config, lib, pkgs, self, ... }:
let
  ports = import "${self}/vars/ports.nix";
  home = "/home/admin";
  repo = "${home}/g/openclaw";
  desktop = "v@v-laptop";
  idFile = "${home}/.ssh/id_pc";

  keyFile = config.sops.secrets.openclaw_openai_key.path;
  tgTokenFile = config.sops.secrets.openclaw_telegram_token_test.path;
  alertsChannelFile = config.sops.secrets.telegram_alerts_channel.path;

  provider = "openai-luna";
  model = "gpt-5.6-luna";

  # Hand-written catalog entry: a custom provider gets no catalog lookup, so the window, output cap
  # and price have to be stated or the agent over-truncates and mis-accounts. apiKey is a sentinel
  # replaced from sops at activation — openclaw has no env-var expansion in its config.
  ocConfig = builtins.toJSON {
    models.providers.${provider} = {
      baseUrl = "https://api.openai.com/v1";
      apiKey = "sops";
      api = "openai-responses";
      models = [{
        id = model;
        name = "GPT-5.6 Luna";
        api = "openai-responses";
        reasoning = true;
        input = [ "text" "image" ];
        contextWindow = 372000;
        maxTokens = 128000;
        cost = { input = 1; output = 6; cacheRead = 0.1; cacheWrite = 1.25; };
      }];
    };
    agents.defaults = {
      model.primary = "${provider}/${model}";
      workspace = "${home}/.openclaw/workspace";
      heartbeat.every = "30m";
    };
    # Routed from Telegram, so the agent needs the message tool for reply/thread-reply/attachment
    # actions. alsoAllow rather than allow: additive on top of the profile, so it stays auditable.
    tools.alsoAllow = [ "group:messaging" ];
    commands.ownerAllowFrom = [ "telegram:718815767" ];
  };
  cfgHash = builtins.hashString "sha256" ocConfig;
in {
  # Only openclaw's own two creds, out of secrets/openclaw.json rather than the whole
  # secrets/users/v/default.json. defaultSopsFile (hosts/rpi5/secrets.json) stays as it is.
  sops.secrets.openclaw_openai_key = {
    sopsFile = "${self}/secrets/openclaw.json";
    key = "openai_api_key";
    owner = "admin";
    mode = "0400";
  };
  sops.secrets.openclaw_telegram_token_test = {
    sopsFile = "${self}/secrets/openclaw.json";
    key = "telegram_token_test";
    owner = "admin";
    mode = "0400";
  };
  # The alert unit reads this one; it already lives in the box's own secrets.json.
  sops.secrets.telegram_alerts_channel.owner = "admin";

  home-manager.users.admin = { lib, ... }: {
    home.packages = [
      pkgs.nodejs_22

      (pkgs.writeShellScriptBin "openclaw" ''
        exec ${lib.getExe pkgs.nodejs_22} "${repo}/openclaw.mjs" "$@"
      '')

      # The full update dance for the openclaw checkout — anything less than all of these steps
      # after moving HEAD leaves the gateway broken (stale dist) or crash-looping (schema drift).
      (pkgs.writeShellScriptBin "openclaw-rebuild" ''
        set -euo pipefail
        cd "${repo}"
        export CI=true COREPACK_ENABLE_DOWNLOAD_PROMPT=0
        export PATH="${pkgs.nodejs_22}/bin:$PATH"
        corepack pnpm install
        corepack pnpm build
        node openclaw.mjs doctor --fix
        systemctl --user restart openclaw-gateway
        sleep 20
        node openclaw.mjs channels status --probe
      '')

      # Exit code IS the contract, and HEARTBEAT.md reads all three branches:
      # 0 = desktop up, 255 = ssh could not reach it (desktop off), anything else = our own
      # tooling is broken. Conflating the last two is what let the heartbeat no-op for months.
      (pkgs.writeShellScriptBin "pc-up" ''
        exec ${lib.getExe pkgs.openssh} -o BatchMode=yes -o ConnectTimeout=5 \
          -o StrictHostKeyChecking=accept-new -i ${idFile} ${desktop} true
      '')

      # Login shell on the far side: `tedi` and the rest live on v's default profile PATH.
      (pkgs.writeShellScriptBin "pc" ''
        [ "$#" -gt 0 ] || { echo "usage: pc <command...>" >&2; exit 2; }
        exec ${lib.getExe pkgs.openssh} -o BatchMode=yes -o ConnectTimeout=5 \
          -o StrictHostKeyChecking=accept-new -i ${idFile} ${desktop} -- bash -lc "$*"
      '')
    ];

    # `onboard --non-interactive` / `config patch` / `channels add` are all idempotent and merge
    # into ~/.openclaw/openclaw.json, so this re-runs safely and fully reproduces config on a clean
    # ~/.openclaw. Gated on the checkout actually being present.
    home.activation.configureOpenclaw = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      node="${lib.getExe pkgs.nodejs_22}"
      oc() { "$node" "${repo}/openclaw.mjs" "$@"; }
      # Each oc call spawns node (~7s on this box, more), and this block only needs to actually run
      # when config inputs change. Stamp over the nix config + secret contents.
      stamp="${home}/.openclaw/.hm-config-stamp"
      want="$( { printf '%s' '${cfgHash}'; cat ${tgTokenFile} ${keyFile} 2>/dev/null; } | ${lib.getExe' pkgs.coreutils "sha256sum"} | cut -d' ' -f1 )"
      if [ -r "$stamp" ] && [ "$(cat "$stamp")" = "$want" ]; then
        echo "configureOpenclaw: config unchanged, skipping"
      elif [ -d "${repo}" ]; then
        # `--auth-choice skip`: onboard's custom-provider flags refuse to overwrite an existing
        # provider id and silently mint `${provider}-2`, `-3`, ... on every re-run, so the model
        # side is left entirely to the patch below.
        oc onboard --non-interactive --accept-risk \
          --mode local \
          --auth-choice skip \
          --gateway-port ${toString ports.openclawGateway} \
          --gateway-bind loopback \
          --no-install-daemon \
          --skip-channels \
          --skip-skills \
          --skip-ui \
          --skip-health \
          || echo "configureOpenclaw: onboard failed (non-fatal); run 'openclaw onboard' manually" >&2

        # --replace-path: providers become exactly what nix declares, so a provider dropped here
        # (or an accidental `${provider}-N`) disappears instead of lingering as a silent failover.
        printf '%s' ${lib.escapeShellArg ocConfig} \
          | ${lib.getExe pkgs.jq} --rawfile k ${keyFile} \
              '.models.providers["${provider}"].apiKey = ($k | rtrimstr("\n"))' \
          | oc config patch --stdin --replace-path models.providers \
          || echo "configureOpenclaw: model patch failed; openclaw is left on whatever onboard wrote" >&2

        # Telegram channel on the *test* bot (distinct token from tg-server's main bot).
        oc plugins enable telegram || true
        oc channels add --channel telegram --token "$(cat ${tgTokenFile})" --name "test_my_nonsense_bot" || true

        mkdir -p "$(dirname "$stamp")" && printf '%s' "$want" > "$stamp"
      else
        echo "configureOpenclaw: ${repo} missing; skipping" >&2
      fi
    '';

    systemd.user.services.sops-nix.Service.RemainAfterExit = true;

    # Runs the checkout at ~/g/openclaw directly via node, from its locally-built dist/ (untracked;
    # produced by `openclaw-rebuild`). The preflight refuses to start on a dist/ built from a
    # different commit than the checkout's HEAD: a stale dist against a moved tree crash-loops on
    # plugin/config validation (2026-07-11 outage), so fail immediately with an actionable message.
    systemd.user.services.openclaw-gateway = {
      Unit = {
        Description = "OpenClaw multi-channel AI gateway (GPT-5.6 Luna)";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
        # Crash-looping forever helps nobody: after the burst, give up and page via telegram.
        StartLimitIntervalSec = 600;
        StartLimitBurst = 20;
        OnFailure = [ "openclaw-gateway-alert.service" ];
      };
      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.writeShellScript "openclaw-preflight" ''
          [ -f "${repo}/openclaw.mjs" ] || { echo "openclaw checkout missing at ${repo}" >&2; exit 1; }
          [ -f "${repo}/dist/build-info.json" ] || { echo "no dist/ at ${repo} — run openclaw-rebuild" >&2; exit 1; }
          built=$(${lib.getExe pkgs.jq} -r .commit "${repo}/dist/build-info.json")
          head=$(${lib.getExe pkgs.git} -C "${repo}" rev-parse HEAD)
          if [ "$built" != "$head" ]; then
            echo "dist/ built from $built but checkout is at $head — run openclaw-rebuild" >&2
            exit 1
          fi
        ''}";
        ExecStart = "${lib.getExe pkgs.nodejs_22} ${repo}/openclaw.mjs gateway --port ${toString ports.openclawGateway}";
        Restart = "on-failure";
        # Without `direct` the unit enters failed between every auto-restart, so OnFailure= pages
        # once per attempt -- 21 identical telegram messages per boot (2026-09-03). Fire only at
        # the limit.
        RestartMode = "direct";
        RestartSec = 5;
        Environment = [ "OPENCLAW_STATE_DIR=${home}/.openclaw" ];
        # This box also runs k3s/prometheus/grafana on 7.9Gi with swap already deep. openclaw is
        # ~1GB RSS on the desktop; the cap is what keeps a leak from taking the cluster with it.
        MemoryHigh = "1G";
        MemoryMax = "1500M";
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.openclaw-gateway-alert = {
      Unit.Description = "Telegram alert when openclaw-gateway exhausts its restart budget";
      Service = {
        Type = "oneshot";
        # Test-bot token, not main: telegram_token_main is currently revoked (401 on getMe,
        # 2026-07-11), and Bot API sends don't conflict with the gateway's getUpdates poll anyway —
        # least of all when this fires, i.e. when the gateway is down.
        ExecStart = "${pkgs.writeShellScript "openclaw-alert" ''
          token=$(cat ${tgTokenFile})
          chat=$(cat ${alertsChannelFile})
          ${lib.getExe pkgs.curl} -fsS -m 10 "https://api.telegram.org/bot$token/sendMessage" \
            -d chat_id="$chat" \
            --data-urlencode text="openclaw-gateway is DOWN on ${config.networking.hostName} (start limit hit). If ${repo} HEAD moved without a rebuild, run: openclaw-rebuild. Logs: journalctl --user -u openclaw-gateway"
        ''}";
      };
    };
  };
}
