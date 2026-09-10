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
   _nix_direnv_manual_reload=1
   _nix_direnv_warn_manual_reload() {
     _nix_refresh_gcroots 2>/dev/null
     _nix_direnv_warning 'cache is out of date. use "nix-direnv-reload" to reload'
   }
   ```
   Written to `$XDG_CONFIG_HOME/direnv/direnvrc`, sourced by direnv **after**
   `lib/hm-nix-direnv.sh` (which defaults the var to 0). Paired with the two
   package overrides in §1b, which is what makes the unconditional `=1` safe.

   ### 1b. Absence is not staleness (2026-09-06)

   The original gate was `compgen -G '*-profile-*.rc'` → `manual_reload=1`, i.e.
   "any cache at all pins the env". `use_nix`/`use_flake` compute three separate
   invalidation reasons and then collapse them:
   ```sh
   if [[ $profile_missing || $profile_rc_missing || $file_nt_profilerc ]]; then
     if [[ $_nix_direnv_manual_reload -eq 1 && -z ${_nix_direnv_force_reload-} ]]; then
       _nix_direnv_warn_manual_reload "$profile_rc"    # ← no rebuild
   ...
   _nix_import_env "$profile_rc"                        # ← sourced regardless
   ```
   Only the third reason should be ignorable. Once `nix-collect-garbage` took a
   closure the `.rc` outlived it, `profile_missing=1` was computed and then
   thrown away, and the dead rc was sourced anyway — and `silent = true` hides
   the one warning that said so. Observed as the shellHook detonating on dangling
   paths: `cargo -Zscript <hash>-cargo_merge.rs` panicking on a deleted argument,
   a wall of `cp: cannot stat '/nix/store/…-unknown'`, and `rustfmt` falling
   through to the rustup shim (`'rustfmt' is not installed for the toolchain`).

   Two `substituteInPlace` edits on `pkgs.nix-direnv` (both hit `use_nix` and
   `use_flake`, 4 sites total) narrow each guard to the stale case:
   - `manual_reload` also requires `profile_missing -eq 0 && profile_rc_missing -eq 0`
   - `allow_fallback` likewise — a failed eval must not resurrect a dead cache as
     "falling back to previous environment"; there is no previous environment.

   With that, the stdlib gate is dead weight: a first load has no rc, so
   `profile_rc_missing` bypasses manual reload on its own.

   The `_nix_direnv_warn_manual_reload` override closes the other half. Upstream
   calls `_nix_refresh_gcroots` only on a cache *hit*; a cache pinned by manual
   reload never takes that path, so its gcroot mtimes freeze from the moment
   `flake.nix` is first touched, and it ages out of what `nh` considers live —
   manufacturing the collectable closure the guards above now refuse to source.

   Verified 2026-09-06 with real `direnv` against a scratch flake, stock lib as
   control (`/tmp/ndtest`, harness discarded):
   | state | stock | patched |
   |---|---|---|
   | no cache | builds | builds |
   | sources newer | pinned, no eval | pinned, no eval, **rc mtime refreshed** |
   | profile dangling, closure gone | `cp: cannot stat …`, broken env | rebuilds, env correct |
   | dead cache + eval fails | broken env, exit 0 | real error, no env |
   | `dirr` | rebuilds | rebuilds |

   Steady-state cost unchanged: 97ms/load patched vs 98ms stock on a cache hit,
   98 vs 100 on the pinned-stale path (5-run means, same machine).

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
