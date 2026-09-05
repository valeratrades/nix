{ config, pkgs, lib, self, inputs, user, ... }:
#############################################################
#
# `valera` on the rpi5 — a personal always-on agent account
# living on a box whose own config (hosts/rpi5) is the EV-invest
# submodule. Nothing here touches that submodule: outputs/default.nix
# grafts this module on with `.extendModules`, so the org repo
# never carries a personal user, personal bot tokens, or personal
# secret declarations.
#
# `admin` (the org's shared login) and `valera` run side by side —
# separate homes, separate home-manager generations under
# /etc/profiles/per-user, separate `systemd --user` instances. The
# only thing that would have made it one-at-a-time is login-gated
# user services, which `linger` removes.
#
#############################################################
let
  # Everything valera's agent needs is in the personal store, not the box's.
  # `key` decouples the /run/secrets name from the lookup name — the box's own
  # secrets.json already owns `telegram_alerts_channel`, and two sops secrets
  # cannot share an output path.
  userSecret = key: {
    inherit key;
    sopsFile = "${self}/secrets/users/v/default.json";
    format = "json";
    owner = "valera";
    mode = "0400";
  };
in
{
  users.users.valera = {
    isNormalUser = true;
    # Deliberately NOT wheel. An LLM drives this account; the blast radius of a
    # prompt injection stops at valera's home rather than at the k3s cluster and
    # every cluster secret on the box (`security.sudo.wheelNeedsPassword = false`
    # in the submodule would otherwise make that a single tool call).
    extraGroups = [ ];
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = user.sshAuthorizedKeys;
    # The account never logs in — the gateway has to survive with nobody attached,
    # and without lingering `systemd --user` is torn down the moment the last
    # session ends (i.e. it would only run while you happened to be ssh'd in).
    linger = true;
  };

  sops.secrets = {
    "valera/openai_api_key" = userSecret "openai_api_key";
    # openclaw drives the *test* bot (@test_my_nonsense_bot). The main token is
    # tg-server's, and a bot token admits exactly one getUpdates consumer.
    "valera/telegram_token_test" = userSecret "telegram_token_test";
    "valera/telegram_alerts_channel" = userSecret "telegram_alerts_channel";
    # One ed25519 key with two jobs: rpi5 -> v-laptop (so the agent can act on the
    # PC when it is up) and the openclaw_workspace deploy key (private repo, and
    # the agent commits its own memory back to it).
    "valera/ssh_key" = userSecret "rpi5_valera_ssh_key";
  };

  # openclaw's own on-disk trail — agent/session logs, per-cron-run jsonl, and the
  # undelivered-message queue — is the one thing on this box that grows without an
  # operator ever looking at it. journald is already capped in the submodule
  # (500M / 1 week), so this covers only what openclaw writes outside it.
  # `e` = prune entries older than the age, leaving the directory itself.
  systemd.tmpfiles.rules = [
    "d /home/valera/.openclaw 0700 valera users -"
    "e /home/valera/.openclaw/logs 0700 valera users 7d"
    "e /home/valera/.openclaw/cron/runs 0700 valera users 14d"
    "e /home/valera/.openclaw/delivery-queue 0700 valera users 14d"
  ];

  home-manager.users.valera = import ./home.nix;
}
