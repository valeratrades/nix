# make `direnv allow` / `nix develop` never touch network unless cache is fully missing

## Goal (restated)
When a dev env is already realized locally, entering it (direnv, or manual
`nix develop`) must do **zero** re-evaluation and **zero** network I/O — even
if `flake.nix`/`flake.lock` changed. Updates are strictly manual. Network is
allowed in exactly one case: the env has **no** local cache at all (never built
here), so there's nothing to reuse.

## Root cause of the old pain
Stock nix-direnv treats "a watched file (`flake.nix`, `flake.lock`, `.envrc`)
is newer than the cache" as **cache invalidated → re-run `nix print-dev-env`**,
which evaluates the flake and, with default `tarball-ttl=3600`, re-checks the
flake registry / tarballs over the network. So every edit (or every rebuild
that bumps mtimes) = online eval.

nix-direnv already ships the exact off-switch: `nix_direnv_manual_reload`
(`_nix_direnv_manual_reload=1`). When set, an out-of-date cache is **used as-is**
with a warning instead of rebuilding. The only missing piece: it must NOT apply
when there is no cache (or you'd get an empty env and a warning, no shell).

## The fix (4 small edits)

1. **`hosts/hm-shared/home.nix`** — `programs.direnv.stdlib`:
   ```sh
   if compgen -G "$(direnv_layout_dir)/*-profile-*.rc" >/dev/null; then
     _nix_direnv_manual_reload=1
   fi
   ```
   Written to `$XDG_CONFIG_HOME/direnv/direnvrc`, sourced by direnv **after**
   `lib/hm-nix-direnv.sh` (which defaults the var to 0). So: cache present →
   manual reload (reuse, no eval, no net); cache absent → normal auto-build.
   Glob matches both real profile names: `flake-profile-<hash>.rc` and
   `nix-profile-<ver>-<sum>.rc`.

2. **`home/config/fish/app_aliases/nix/__main__.fish`** — `nix` function wrapping
   `nix develop`: probe `print-dev-env --offline --max-jobs 0`; on success run
   `nix develop --offline`, else fall through to online. `--offline` can never
   hit the network by definition, so the worst online case is a genuinely
   missing env. (Direnv is the daily path; this only covers manual `nix develop`.)

3. **`home/config/fish/app_aliases/direnv.fish`** — `dirr` now force-reloads via
   `.direnv/bin/nix-direnv-reload` (rebuild in place, keeps gcroots) instead of
   `rm -r .direnv` (which also nukes the gcroots). This is THE manual update path
   now that auto-reload is off.

4. **`os/nixos/configuration.nix`** — `nix.settings`:
   - `tarball-ttl = 4294967295` — stop the hourly registry/tarball re-fetch.
   - `keep-outputs = true` — GC keeps the build closure of gcrooted dev shells,
     so direnv caches stay usable offline after `nix-collect-garbage`.

## Verified empirically (2026-07-11, all under `unshare -rn` = zero network)
Scratch flake pinning the repo's locked nixpkgs, real `pkgs.nix-direnv` lib +
the stdlib snippet, real `direnv`:
- **First load, no cache**: `_nix_direnv_manual_reload=0` → builds, "Renewed cache",
  `flake-profile-*.rc` created. ✅ (fresh project still works)
- **Second load, `flake.nix`/`lock`/`.envrc` touched newer, no network**:
  → "cache is out of date. use nix-direnv-reload to reload" and the **cached env
  loads** (`MARKER=odtest_v1`), rc=0. ✅ (the whole point — stale sources, still
  offline, still get the env)
- Gating glob unit-checked against `flake-profile-deadbeef.rc`: present→1, absent→0. ✅
- All four edited files parse (`nix-instantiate --parse`, `fish -n`). ✅

## Not yet done / caveats
- **Not applied to the live system** — needs a `nixos-rebuild switch` (or
  `home-manager switch`) to take effect. The stdlib and nix.conf changes only
  land after a rebuild.
- `nix develop` probe under-predicts: a shell that was `print-dev-env`'d but
  never *realized* passes the probe, then `nix develop --offline` source-builds
  its closure **offline** (observed: 217 derivs on the bootstrap-stdenv scratch
  flake). No network is touched (goal met), but it's slow. Not a normal state
  for a real project (either fully built+gcrooted, or nothing). Left as is.
- The rpi5/server hosts use their own `programs.direnv` blocks
  (`hosts/rpi5/home.nix`, `os/nixos/server-standalone.nix`) — the stdlib gate is
  only in `hm-shared`. Add the same `stdlib` there if those hosts need it.
- Related prior work: `rust-scripts-offline.md` (same "cached but wants network"
  class of bug for `cargo -Zscript`), and the gcroot patch for nix-direnv
  issue #546 already in `hm-shared/home.nix`.
