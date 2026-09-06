# rpi5-valera — the always-on agent account

A second user on the rpi5, running one openclaw gateway. `admin` (the shared
org login, `hosts/rpi5`) and `valera` run **side by side** — separate homes,
separate home-manager generations under `/etc/profiles/per-user`, separate
`systemd --user` instances. There is no one-at-a-time constraint anywhere in
NixOS or home-manager; the only thing that would have looked like one is that a
user's services die with their last login session, which `linger = true` removes.

`hosts/rpi5` is the EV-invest submodule and stays free of personal config. This
module is grafted on from the parent repo instead:

```nix
# outputs/default.nix
rpi5 = (import .../hosts/rpi5/system.nix { ... }).extendModules {
  modules = [ .../hosts/rpi5-valera ];
};
```

## Shape

```
            tailnet — a mesh, so this is one hop, not a reverse tunnel
  ┌──────────────────────────┐                ┌───────────────────────────┐
  │ rpi5           always on │                │ v-laptop    intermittent  │
  │                          │  pc <cmd>      │                           │
  │  openclaw-gateway ───────┼───────────────▶│  tedi / monitors /        │
  │  workspace (git)         │  ssh, sops key │  Clockify / ~/s ~/g ~/nix │
  │  pc-up ─── probe ────────┼───────────────▶│                           │
  └──────────────────────────┘                │  openclaw: OFF            │
                                              └───────────────────────────┘
```

## One agent, not two

`myvars.valera.openclaw` is now `false`, so the laptop no longer runs a gateway.
It cannot run in both places: a Telegram bot token admits exactly one `getUpdates`
consumer, and `openclaw_workspace` — the agent's memory, which it commits to —
admits one writer. Turning the laptop's back on means turning this one off first.

## The PC-up split

`HEARTBEAT.md` in the workspace runs `pc-up` and branches on its **exit code**, so
a heartbeat with the PC down costs one tool call rather than a turn of LLM
judgment. Everything the work checkup measures — screen, Clockify, local git —
only exists while the PC is up, so there is nothing to weigh when it is down.

`pc-up` is an ssh handshake, not a tailscale peer lookup: the question is "can I
run a command over there right now", and a suspended laptop reads as an online
peer for a while yet. `pc <cmd>` runs the command in a login fish shell over
there; it pipes the command over stdin rather than argv, because ssh flattens
argv into one string for the far shell to re-parse.

There is **no discovery daemon**. Nothing fires on the PC's up-edge, so a 5–10s
poll would only maintain a cached flag that a 1s probe answers on demand. Add one
if something ever needs to happen *at the moment* the PC appears.

## What is not replicated from the laptop

- **The checkout and its build.** `pkgs.openclaw` (nixpkgs-unstable, which is
  pinned for this and nothing else) instead of `~/g/openclaw` + pnpm, so there is
  no `dist/`-vs-HEAD preflight and no rebuild dance on a box that is already
  swapping.
- **litellm.** It exists on the laptop because `openai-completions` cannot carry a
  gpt-5.6 tool call. openclaw speaks `openai-responses` natively, so the provider
  dials `api.openai.com` directly and there is no proxy daemon here.

## Blast radius

`valera` is deliberately not in `wheel`. An LLM drives this account, and the
submodule sets `security.sudo.wheelNeedsPassword = false`, so wheel would put the
k3s cluster and every cluster secret on the box one tool call from a prompt
injection.

Its ssh key (sops: `secrets/users/v` → `rpi5_valera_ssh_key`) is reachable from
`myvars.valera.agentKeys`, appended **only** in `os/nixos/configuration.nix`. It is
not in `sshAuthorizedKeys`, because the submodule hands that list to `root` — which
would give the agent root on the box it runs on.

## Growth

journald is capped host-wide by the submodule (500M / 1 week). What openclaw
writes outside it — agent logs, per-cron-run jsonl, the undelivered-message queue
— is pruned by the `systemd.tmpfiles` rules in `default.nix`, since nothing else
ever looks at those directories.

## The one recurring cost

`openclaw` has no aarch64 build on cache.nixos.org, and this box cannot build a TS
monorepo from source in any reasonable time. So each version bump is: build it on
the laptop under `binfmt` aarch64, `cachix push valeratrades`, then rebuild here.
`nix.settings.extra-substituters` in `default.nix` is what makes the Pi pick it up
without `--accept-flake-config`.

That is the whole reason the flake's `valeratrades.cachix.org` exists (see the
TODO at the top of `flake.nix`) — this is its first real consumer.

## Manual, once

1. Register `agentKeys`' public half as a **write** deploy key on
   `valeratrades/openclaw_workspace` (done: key id `162413281`).
2. `nixos-rebuild switch` on the box. Activation clones the workspace and runs
   `openclaw onboard` + `config patch` + `channels add`; all three are idempotent
   and stamped, so later switches skip them unless the config or a secret moved.
3. The gateway refuses to start without a workspace clone rather than inventing an
   empty one — if it does, the deploy key is the thing to check.
