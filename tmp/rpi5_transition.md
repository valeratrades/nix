# rpi5 transition: AWS fallback → the new card

The platform has been served from `evinvest-fallback` (EC2 t4g.large, eu-west-3) since
the Pi's card burned (~2026-09-12). The new card was built from `hosts/rpi5` @ `146ce5e`
and is **born gated**: it boots, joins wifi + tailscale, runs k3s with no Flux, and keeps
Postgres / Redis / TigerBeetle / cloudflared / the R2 shippers skipped until the restore
routine writes `/var/lib/fallback/{restored,serving,verified}`.

```
            now                                   after
 ┌──────────────────────┐              ┌──────────────────────┐
 │ evinvest-fallback    │  failback    │ evinvest-fallback    │ terminate
 │ writer, cloudflared ●├─────────────►│ k3s+cf stopped ○     ├──────────► gone
 │ ships → R2           │  final dump  └──────────────────────┘
 └──────────────────────┘      │
                               ▼  R2: postgres/rpi5, tb/<id>/replica-*, backups/redis
 ┌──────────────────────┐   restore pi   serve pi        verify pi
 │ rpi5 (new card)      ├──────────────►──────────────►─────────────► writer, ships → R2
 │ gated ○, k3s no Flux │   stores+gate  fence,Flux,cf   shippers on
 └──────────────────────┘
          outage window: failback ─► serve pi  (≈30–60 min, Flux's first converge is ~20m)
```

**The one invariant:** never two live connectors / writers. `serve pi` refuses while the
instance still has an active cloudflared/k3s/postgres, and the public hostnames must
answer 530 (no origin) first.

## 0. Before the window (no outage)

- [ ] Merge together: EV-invest/rpi5.nix#43 + EV-invest/devops#22 (fallback). Then
      EV-invest/gitops#60 → EV-invest/devops#23 (social_networks). After merging, repoint
      the nix repo's submodules at `main` of each and commit.
- [ ] Tailscale admin console: **delete the old `rpi5` machine** (offline since ~09-12),
      or the card joins as `rpi5-1` and `rpi5.taila74a7d.ts.net` points at nothing.
- [ ] `tailscale_auth_key` was minted ~2026-06-28 → **expires ~2026-09-26**. If the card
      first boots after that, mint a reusable key, `sops hosts/rpi5/secrets/host.json`,
      and it only matters on first bring-up (state persists after). Until then the card is
      still reachable on the LAN as `rpi5.local`.
- [ ] Insert card, power on (wifi; no ethernet needed — it's pre-enrolled). Then:
      ```sh
      ssh admin@rpi5.local 'systemctl is-active k3s tailscaled cloudflared-tunnel postgresql redis-ev tigerbeetle-0'
      # expect: active active inactive inactive inactive inactive   ← gated, correct
      ssh admin@rpi5.local 'sudo tailscale status | head -3; ls /run/secrets | wc -l'
      ssh -A admin@rpi5.local 'bash -s' < hosts/rpi5/bootstrap.sh   # /etc/nixos clone only
      ```
      Host key is already pinned in `~/.ssh/known_hosts` (backup: `known_hosts.bak-rpi5`).
- [ ] If the card's system is older than `main` after the merges: on the box,
      `sudo nixos-rebuild switch --flake '/etc/nixos?submodules=1#rpi5'`. The gates hold
      through a switch.
- [ ] `cd ~/nix/hosts/devops/fallback && ./fallback.sh status` — note the newest R2
      objects and that the instance is `running`.

## 1. The window

Run from `~/nix/hosts/devops/fallback` (fallback.sh wants the nix checkout as FLAKE_ROOT),
laptop on the home LAN (`PI=root@rpi5` resolves via the `rpi5` ssh alias → `rpi5.local`;
off-LAN, edit it to the tailnet name).

1. **Final Redis dump.** `failback` does NOT force it (it's an in-cluster CronJob, 05:03
   daily), and it stops k3s. Take it first, while the cluster is still up:
   ```sh
   ssh root@<instance-ip> 'k3s kubectl -n apps create job --from=cronjob/backup-redis redis-final \
     && k3s kubectl -n apps wait --for=condition=complete job/redis-final --timeout=10m'
   ```
   Note: writes to Redis between this and step 2 are lost. That's acceptable for concierge/banking
   Redis (sessions/queues); Postgres and TigerBeetle are the durable stores and failback
   proves them.
2. `./fallback.sh failback` — stops cloudflared then k3s, forces pg + 3× TB backups, and
   **fails unless R2 holds objects newer than the quiesce**. Outage starts here.
3. `./fallback.sh restore pi` — pulls pg_dumpall / rdb / 3 replica files into the Pi,
   writes `restored`, starts the stores, re-applies the signer role, prints row counts.
   Compare the counts against what `status` showed on the fallback.
4. `./fallback.sh serve pi` — fence (public hostnames must be 530/5xx, the instance's
   units inactive), then Flux bootstrap (`--timeout=20m`), `k3s-secrets-*` re-render,
   then `serving` + cloudflared. **Outage ends when this lands.**
5. `./fallback.sh verify pi` — public health, piggybank + concierge Ready, tb_accounts,
   signer scram login, tg-sync. Only on success does it write `verified`, releasing the
   Pi's shippers.
6. `./fallback.sh terminate` (type the instance id). Also: `aws ec2 describe-volumes`
   for any orphaned gp3 with tag `ManagedBy=devops`.

If step 3–5 fails: the Pi is not an origin yet and the fallback's data is safe in R2.
Either fix and re-run the failed verb, or bring the fallback back: on the instance
`systemctl start k3s && systemctl start cloudflared-tunnel` (its `serving` gate still
exists). Never both.

If TigerBeetle won't view-change: banking's `nix run .#new-replica` (`tigerbeetle
recover`) against the lagging replica. **Never `format`.**

## 2. After (same day / next morning)

- [ ] Grafana: `devops.evinvest.ltd` — Cloudflare public hostname for Grafana points at a
      NodePort on the box. Confirm it still resolves (the README says read the port off the
      dashboard).
- [ ] Next morning: R2 has `postgres/rpi5/all-<today>.sql.gz` (01:15), `tb/.../replica-*`
      (staggered), `backups/redis/<today>` (05:03), from the Pi.
- [ ] Discord alert webhooks render (`k3s-secrets-discord`), REA came up via its
      litestream initContainer.
- [ ] server_upkeep alerting on the Pi (telegram).

## 3. social_networks onto the Pi (after §2, no platform risk)

Today: started by hand on the laptop; state in `~/.local/state/social_networks/`
(telegram sessions `@valeratrades.session` / `_dm.session`, `skool_cookies.json`,
`gmail_tokens.json`, `db.sqlite3` = email's processed set). Rolodex stays on the laptop
(its own `_rolodex.session` + the records dir).

1. **Stop every laptop daemon** first (dms, telegram-channel-watch, twitter, email,
   youtube). The same telegram session live from two IPs at once gets revoked
   (AUTH_KEY_DUPLICATED).
2. Seed the PVC (`personal/social-networks-data`, binds on first consumer):
   ```sh
   k=/etc/rancher/k3s/k3s.yaml; ssh root@rpi5 "KUBECONFIG=$k k3s kubectl -n personal run sn-seed \
     --image=busybox --restart=Never --overrides='{\"spec\":{\"securityContext\":{\"runAsUser\":65534,\"runAsGroup\":65534},\"containers\":[{\"name\":\"sn-seed\",\"image\":\"busybox\",\"command\":[\"sleep\",\"3600\"],\"volumeMounts\":[{\"name\":\"d\",\"mountPath\":\"/data\"}]}],\"volumes\":[{\"name\":\"d\",\"persistentVolumeClaim\":{\"claimName\":\"social-networks-data\"}}]}}'"
   tar -C ~ -cf - .local/state/social_networks | ssh root@rpi5 "KUBECONFIG=$k k3s kubectl -n personal exec -i sn-seed -- tar -C /data -xf -"
   ssh root@rpi5 "KUBECONFIG=$k k3s kubectl -n personal delete pod sn-seed"
   ```
   (HOME=/data in the image, so state lands at `/data/.local/state/social_networks`.)
3. Check the Secret exists: `k3s kubectl -n personal get secret kubernetes-social-networks`.
4. In `~/s/ev_invest/devops` `flake.nix`: `socialNetworksDaemons = [ "dms"
   "telegram-channel-watch" "twitter" ];`. Seed the tag by hand in
   `gitops/clusters/rpi5/tenants/valeratrades/manifests.yaml` (one line anywhere:
   `image: ghcr.io/valeratrades/social_networks:v0.3.22`). Then `nix run .#materialize`,
   commit gitops + devops, PR, merge. Flux picks it up. From then on, image automation
   bumps the tag on each `v*` release.
5. `email` + `youtube` need Claude: ask_llm runs the `claude` CLI with
   `CLAUDE_CODE_OAUTH_TOKEN`. The laptop's `CLAUDE_TOKEN` is an **API key**
   (`sk-ant-api…`), which that variable doesn't take. Run `claude setup-token`, then in
   one commit: add `claude_code_oauth_token` to `scopes.nix` `tiers.personal` and to
   `secrets/personal.json`, and set `llm.claude_token` to its placeholder in
   `personal.nix`. Only then add `email`/`youtube` to the list.
6. Watch: `k3s kubectl -n personal logs -f deploy/social-networks-dms`. Skool mints
   cookies with the image's chromium (`--no-sandbox`, /tmp is an emptyDir).

Changing which daemons run later = edit the list, materialize, merge.

## 4. Optional cleanup (once the fallback is gone)

- `/var/lib/fallback/*` is now every box's gate path; renaming it (e.g.
  `/var/lib/restore-gate`) is safe only with the fallback terminated: change
  `platform.nix` + `fallback.sh` together, and on the Pi
  `mv /var/lib/fallback /var/lib/restore-gate` **before** the switch, or the switch
  restarts postgres into a skipped condition.
- `rea_admin_token` in `secrets/platform.json` is still the literal `CHANGEME`.
