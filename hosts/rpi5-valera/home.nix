{ config, pkgs, lib, self, inputs, ... }:
#############################################################
#
# valera's home on the rpi5: one always-on openclaw agent.
#
# It is the *only* live instance — see the note on
# `myvars.valera.openclaw` in vars/default.nix. The laptop's copy
# is off, because one Telegram bot token admits one getUpdates
# consumer and one workspace repo admits one writer.
#
# Differences from the laptop's setup (hosts/v-laptop/home.nix),
# both of which delete machinery rather than port it:
#   - packaged openclaw, not the ~/g/openclaw checkout, so there is
#     no pnpm build, no dist/-vs-HEAD preflight and no rebuild dance
#     on a box that is already swapping.
#   - the provider talks to OpenAI directly over `openai-responses`,
#     so the litellm proxy the laptop needs is not replicated here.
#     litellm only existed because `openai-completions` cannot carry
#     a gpt-5.6 tool call; the responses API can.
#
#############################################################
let
  ports = import "${self}/vars/ports.nix";

  # nixpkgs-unstable, not the box's pinned nixpkgs (nixos-raspberrypi's, which
  # carries no openclaw at all). Nothing else in the repo reads pkgs-unstable, so
  # this pin moves on openclaw's schedule alone.
  # The insecure marking is not a CVE — it is nixpkgs flagging "an LLM with tool
  # access parses untrusted input", which is the thing being asked for here.
  pkgs-oc = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowInsecurePredicate = p: (p.pname or "") == "openclaw";
  };

  laptop = "v-laptop.taila74a7d.ts.net";
  stateDir = "${config.home.homeDirectory}/.openclaw";
  workspace = "${stateDir}/workspace";
  sshKey = "/run/secrets/valera/ssh_key";

  # The whole PC-up/PC-down split, in an exit code. Not a poll loop and not a
  # cached flag: the question the agent actually has is "can I run a command over
  # there right now", and an ssh handshake answers exactly that — a laptop that is
  # suspended still reads as an online tailscale peer for a while, so peer state
  # would answer a different, wronger question.
  pc-up = pkgs.writeShellScriptBin "pc-up" ''
    exec ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=5 ${laptop} true
  '';
  # Login shell, because the work-checkup skill's commands (tedi, CLAUDE_TOKEN,
  # WAYLAND_DISPLAY) only exist in one over there.
  #
  # The command goes over stdin rather than in argv: ssh flattens argv into a single
  # string for the remote shell to re-parse, so anything passed that way has to be
  # quoted for a shell on the far side that isn't the one quoting it. Piping it
  # sidesteps the whole class of bug. Nothing this runs reads stdin itself.
  pc = pkgs.writeShellScriptBin "pc" ''
    [ $# -gt 0 ] || { echo "usage: pc <command...>   (runs it on ${laptop})" >&2; exit 2; }
    printf '%s\n' "$*" | ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=5 ${laptop} "fish -l"
  '';
in
{
  home.stateVersion = "25.11";

  home.packages = [
    pkgs-oc.openclaw
    pc-up
    pc
    pkgs.git
    pkgs.jq
    pkgs.ripgrep
    pkgs.openssh
  ];

  programs.bash.enable = true;
  programs.git = {
    enable = true;
    settings = {
      user.name = "openclaw (rpi5)";
      user.email = "v79166789533@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
      safe.directory = "*";
    };
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      # accept-new rather than the laptop's `no` + /dev/null: on a tailnet the
      # threat is not a MITM, but silently re-trusting a changed key is still a
      # thing worth being told about.
      "${laptop}" = {
        user = "v";
        identitiesOnly = true;
        identityFile = [ sshKey ];
        extraOptions.StrictHostKeyChecking = "accept-new";
      };
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identitiesOnly = true;
        identityFile = [ sshKey ];
      };
    };
  };

  # Clone-if-absent only. The workspace is the agent's own memory and the agent
  # commits to it, so an automatic pull here would be a second writer racing it.
  home.activation.cloneOpenclawWorkspace = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "${workspace}/.git" ]; then
      mkdir -p "${stateDir}"
      GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i ${sshKey} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
        ${pkgs.git}/bin/git clone git@github.com:valeratrades/openclaw_workspace.git "${workspace}" \
        || echo "cloneOpenclawWorkspace: clone failed; is ${sshKey} registered as a deploy key?" >&2
    fi
  '';

  # Mirrors hosts/v-laptop/home.nix's configureOpenclaw: `onboard` + `config patch`
  # + `channels add` are idempotent and merge into ~/.openclaw/openclaw.json, so
  # this reproduces the whole config on a clean state dir and re-runs safely.
  home.activation.configureOpenclaw =
    # After the clone: `onboard` writes into the state dir, and a half-configured
    # agent pointed at a workspace that does not exist yet is the one ordering that
    # actually bites.
    let
      provider = "openai-direct";
      model = "gpt-5.6-luna";
      # litellm reports no metadata for these models and the direct API reports it
      # only per-request, so the window, output cap and price are stated here or the
      # agent over-truncates and mis-accounts. Same numbers as the laptop's entry.
      ocConfig = builtins.toJSON {
        models.providers.${provider} = {
          baseUrl = "https://api.openai.com/v1";
          apiKey = "@APIKEY@";
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
          inherit workspace;
          heartbeat.every = "30m";
        };
        # Routed from Telegram, so the agent needs the message tool for
        # reply/thread-reply/attachment actions.
        tools.alsoAllow = [ "group:messaging" ];
        commands.ownerAllowFrom = [ "telegram:718815767" ];
      };
      cfgHash = builtins.hashString "sha256" ocConfig;
    in
    lib.hm.dag.entryAfter [ "cloneOpenclawWorkspace" ] ''
      keyFile="/run/secrets/valera/openai_api_key"
      tgTokenFile="/run/secrets/valera/telegram_token_test"
      oc() { ${lib.getExe pkgs-oc.openclaw} "$@"; }
      # Each oc call spawns node; this block is idempotent but only needs to run
      # when its inputs change. Stamp over the nix config + secret contents.
      stamp="${stateDir}/.hm-config-stamp"
      want="$( { printf '%s' '${cfgHash}'; cat "$keyFile" "$tgTokenFile" 2>/dev/null; } | ${pkgs.coreutils}/bin/sha256sum | cut -d' ' -f1 )"
      if [ ! -r "$keyFile" ]; then
        echo "configureOpenclaw: $keyFile not readable; skipping" >&2
      elif [ -r "$stamp" ] && [ "$(cat "$stamp")" = "$want" ]; then
        echo "configureOpenclaw: config unchanged, skipping"
      else
        # --auth-choice skip: onboard's custom-provider flags refuse to overwrite an
        # existing provider id and silently mint `${provider}-2`, `-3`, ... on every
        # re-run, so the model side is left entirely to the patch below.
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

        # openclaw has no env-var expansion in its config, so the key is materialized
        # here rather than referenced. --replace-path: providers become exactly what
        # nix declares, so one dropped here disappears instead of lingering as a
        # silent failover.
        printf '%s' ${lib.escapeShellArg ocConfig} \
          | ${lib.getExe pkgs.jq} --rawfile k "$keyFile" '.models.providers["${provider}"].apiKey = ($k | rtrimstr("\n"))' \
          | oc config patch --stdin --replace-path models.providers \
          || echo "configureOpenclaw: model patch failed; openclaw is left on whatever onboard wrote" >&2

        if [ -r "$tgTokenFile" ]; then
          oc plugins enable telegram || true
          oc channels add --channel telegram --token "$(cat "$tgTokenFile")" --name "test_my_nonsense_bot" || true
        else
          echo "configureOpenclaw: $tgTokenFile not readable; skipping telegram channel" >&2
        fi
        printf '%s' "$want" > "$stamp"
      fi
    '';

  systemd.user.services.openclaw-gateway = {
    Unit = {
      Description = "OpenClaw multi-channel AI gateway (GPT-5.6 Luna, direct OpenAI)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      # Crash-looping forever helps nobody: after the burst, give up and page.
      StartLimitIntervalSec = 600;
      StartLimitBurst = 20;
      OnFailure = [ "openclaw-gateway-alert.service" ];
    };
    Service = {
      Type = "simple";
      # Without the workspace, openclaw creates an empty one and runs with no
      # memory, no skills and no HEARTBEAT — and clone-if-absent above will then
      # never fire again, because the directory now exists. Refuse instead.
      ExecStartPre = "${pkgs.writeShellScript "openclaw-preflight" ''
        [ -d "${workspace}/.git" ] || {
          echo "no workspace clone at ${workspace} — check /run/secrets/valera/ssh_key against the openclaw_workspace deploy key, then re-run home-manager activation" >&2
          exit 1
        }
      ''}";
      ExecStart = "${lib.getExe pkgs-oc.openclaw} gateway --port ${toString ports.openclawGateway}";
      Restart = "on-failure";
      # Without `direct` the unit enters failed between every auto-restart, so
      # OnFailure= pages once per attempt. Fire only at the limit.
      RestartMode = "direct";
      RestartSec = 5;
      Environment = [
        "OPENCLAW_STATE_DIR=${stateDir}"
        # The agent shells out to `pc` / `pc-up`; a systemd user unit does not
        # inherit a login shell's PATH.
        "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
      ];
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.openclaw-gateway-alert = {
    Unit.Description = "Telegram alert when openclaw-gateway exhausts its restart budget";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "openclaw-alert" ''
        token=$(cat /run/secrets/valera/telegram_token_test)
        chat=$(cat /run/secrets/valera/telegram_alerts_channel)
        ${pkgs.curl}/bin/curl -fsS -m 10 "https://api.telegram.org/bot$token/sendMessage" \
          -d chat_id="$chat" \
          --data-urlencode text="openclaw-gateway is DOWN on rpi5 (start limit hit). Logs: ssh valera@rpi5 journalctl --user -u openclaw-gateway"
      ''}";
    };
  };
}
