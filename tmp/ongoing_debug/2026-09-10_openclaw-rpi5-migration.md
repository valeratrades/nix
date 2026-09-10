# openclaw was never moved to rpi5 — and the heartbeat silently self-disables

## Problem

The intent (documented in `~/.openclaw/workspace/`) is that openclaw runs on the
always-on rpi5, heartbeats every 30m, checks whether the desktop is up, and if so
runs `work-checkup` against it over reverse SSH. None of the three legs exist.
Worse, the heartbeat *appears* healthy: it fires, takes the "PC is off" branch
unconditionally, replies `HEARTBEAT_OK`, and stops. No error, no alert, no work
checkup — ever.

## State as of 2026-09-10

```
      DESIGNED                                  ACTUAL
 ┌──────────────────┐                    ┌──────────────────┐
 │  rpi5 (always-on)│                    │  rpi5            │
 │  openclaw gateway│                    │  (no openclaw,   │
 │  heartbeat 30m   │                    │   no node, no    │
 │        │         │                    │   ~/.openclaw,   │
 │     pc-up ───────┼──ssh──▶ v-laptop   │   no ~/g)        │
 │        │         │                    │       ✗ no privkey
 │   work-checkup ──┼──ssh──▶ tedi/      └──────────────────┘
 │                  │        clockify
 └──────────────────┘                    ┌──────────────────┐
                                         │  v-laptop        │
                                         │  openclaw gateway│  ← still here
                                         │  heartbeat 30m   │
                                         │      │           │
                                         │   pc-up → 127    │  ← cmd not found
                                         │      │           │
                                         │   "PC is off"    │  ← always
                                         │   HEARTBEAT_OK   │
                                         │   (work-checkup  │
                                         │    never runs)   │
                                         └──────────────────┘
```

### Leg 1 — openclaw on rpi5: absent

- `hosts/rpi5/` contains zero `openclaw` references (`grep -rni openclaw hosts/rpi5/` → nothing).
- On the box: no `~/.openclaw`, no `~/g`, no `node` on PATH.
- `vars/default.nix` gates openclaw on `user.openclaw`, true only for `valera`
  (→ `hosts/v-laptop/home.nix:182`). rpi5 does not go through that machinery at
  all: `hosts/rpi5/default.nix` is a self-contained
  `nixos-raspberrypi.lib.nixosSystem`, "deliberately NOT wired through the
  x86_64/desktop machinery". So there is no `user.openclaw = true` to flip — the
  service definition would have to be lifted out of `hosts/v-laptop/home.nix`
  into something both hosts import.
- No commit ever attempted this. `git log --grep=openclaw` → 4 commits, all
  engine/port changes on v-laptop.

Conclusion: not "faulty logic". **The migration was never started.** Only the
workspace-side prose (`HEARTBEAT.md`, `skills/work-checkup/SKILL.md`, which opens
with "You run on the rpi5") was written, ahead of any implementation.

### Leg 2 — `pc-up` / `pc`: do not exist anywhere

- `HEARTBEAT.md:3` → "Run `pc-up`."
- `work-checkup/SKILL.md` → "`pc <command>` runs a command there in a login shell;
  it is the only way to reach `tedi`, Clockify, the monitors and the local git repos."
- Neither is defined in the workspace repo, in `~/nix`, on v-laptop's PATH, or on
  rpi5's PATH. `~/.openclaw/workspace/scripts/` has healthcheck/cron-spend/
  tg-transcribe/gcal — no `pc`.

This is the active-harm bug. `pc-up` → exit 127 → non-zero → HEARTBEAT.md's
"PC is off" branch → `HEARTBEAT_OK`, stop. Heartbeat is firing (`agents.defaults.heartbeat
= {"every": "30m"}` in `openclaw.json`, gateway up 47m, `[heartbeat] started` in
journal) and doing nothing, indistinguishably from doing its job.

### Leg 3 — reverse SSH rpi5 → desktop: not configured

- rpi5 `~/.ssh/` holds only `authorized_keys` + `agent/`. **No private key.**
- v-laptop's `authorized_keys` (`vars/default.nix:3-7`) lists 3 keys:
  `valeratrades@gmail.com`, `root@v-laptop`, `ev`. No rpi5 identity.
- Live test from rpi5: `ssh v-laptop` → `admin@v-laptop: Permission denied
  (publickey,password,keyboard-interactive)`. Note the user is also wrong —
  rpi5's user is `admin`, the desktop's is `v`, so even with a key it needs
  `v@v-laptop` or a `Host` block.
- Tailscale itself is fine: rpi5 sees `v-laptop 100.76.254.47 active; direct`.
  Name resolution and connectivity are not the problem; authn is.

### Leg 4 — workspace ↔ GitHub: content synced, tracking broken

Premise here was wrong. The heartbeat file **is** defined and **is** on GitHub:

- `~/.openclaw/workspace/HEARTBEAT.md` exists locally (commit `f362ca2`,
  "heartbeat: gate on pc-up, route work-checkup through `pc`").
- `git ls-remote --heads origin` → `f362ca2 refs/heads/main` — same SHA. Pushed.

What is broken is the local tracking: local branch is `master` tracking
`origin/master`, which no longer exists on the remote (remote is `main`).
So `git fetch origin` → `fatal: couldn't find remote ref refs/heads/master`, and
`git status` reports a phantom `[ahead 1]`. Cosmetic today, but it means the
checkout can never pull, so once rpi5 *is* the writer, the desktop copy silently
diverges. Fix: `git branch -m master main && git branch -u origin/main`.

Also untracked: `openclaw-workspace-state.json` (should be gitignored).

## Ruled out

- **rpi5 down / unreachable** — no. Up 70 days, SSH fine, Tailscale fine.
  (Load average ~5.0 on a 4-core Pi is worth a separate look; k3s.)
- **Gateway crashed on the desktop** — no. `openclaw-gateway.service` active,
  restarts are ordinary (7 `[heartbeat] started` in 24h ≈ service restarts, not
  heartbeat ticks).
- **Missing heartbeat config** — no. `agents.defaults.heartbeat = {"every":"30m"}`.
- **Missing HEARTBEAT.md** — no, see Leg 4.

## Order of work when picking this up

1. Write `pc` and `pc-up` first, and make the heartbeat **fail loud** instead of
   treating a broken tool as "PC is off". Right now a typo in a script name is
   indistinguishable from a sleeping desktop — that's the class of bug that hides
   the other three. Cheapest version: `pc-up` = `ssh -o BatchMode=yes -o
   ConnectTimeout=5 v@v-laptop true`; distinguish exit 255 (unreachable → PC off)
   from 127/other (tooling broken → alert).
2. Add rpi5's key to `sshAuthorizedKeys` in `vars/default.nix` and generate the
   keypair on rpi5. Add a `Host v-laptop / User v` block. Verify leg 3 in isolation.
3. Only then move the gateway. Requires factoring `systemd.user.services.
   openclaw-gateway` out of `hosts/v-laptop/home.nix:182` into a shared module,
   plus aarch64 node + a `~/g/openclaw` checkout + sops secrets on rpi5, and
   deciding whether the desktop keeps a gateway at all (two gateways on one
   Telegram token = two concurrent `getUpdates` = conflict; cf. the note at
   `hosts/rpi5/default.nix` on `telegram_token_main`).
4. Fix the workspace branch tracking (Leg 4) before rpi5 becomes the writer.
