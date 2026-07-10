# rust scripts (cargo -Zscript via nix-run-cached) failing offline

## Problem
Daily-driver rust scripts (`bluetooth`, `2fa`, ...) run via
`home/scripts/nix-run-cached` (shebang wrapper around `cargo -Zscript`).
Without network they died with:
```
failed to download from `https://index.crates.io/config.json`
[6] Could not resolve hostname
```
even though deps were fully cached and the script had been compiled many times.

## Key facts discovered (verified empirically, 2026-07-10)
- **`cargo -Zscript --offline` works for scripts cargo has NEVER built**, as long
  as the crates are in `~/.cargo/registry`. Resolution uses the local index cache.
  No per-script state needed to go offline.
- Scripts are invoked via fish aliases pointing at `/nix/store/<hash>-source/home/scripts/*.rs`
  — **the store path changes on every home-manager switch**. Anything keyed by
  script *path* dies on every rebuild. (Cargo itself keys its target dir by
  script *content*, see the `sudo 2fa` comment in nix-run-cached.)
- The `.rs` shebang points at the **working-tree** wrapper
  (`/home/v/nix/home/scripts/nix-run-cached`), so wrapper edits are live without
  a home-manager switch.
- cargo exit 101 is ambiguous: compile error, program panic, AND offline
  resolution failure all exit 101.
- Offline resolution failures reliably contain the word `offline` in stderr
  ("As a reminder, you're using offline mode (--offline)..."). Compile errors don't.
- `cargo build -Zscript --manifest-path foo.rs` works, shares the run cache,
  no-op costs ~120ms. Build-only = no program output on stderr, safe to capture
  (capturing the *run*'s stderr would break tty detection / interactivity).
- Second network dependency hiding in the wrapper: if the nix toolchain store
  path gets GC'd, the wrapper re-evals a **GitHub flake** (`builtins.getFlake
  "github:oxalica/rust-overlay/..."`) → network at some random future run.

## Attempts, in order
1. **Marker keyed by script path md5, content hash inside** (pre-existing code).
   FAILED: store path changes every home-manager switch → all markers
   invalidated every rebuild → first run of each script went online.
2. **Marker keyed by content hash** (`.offline-ok/<md5 of content>`).
   Worked, but wrong by design: any script edit (or marker loss) demanded
   network *at run time* even with all deps cached. Also the fix itself wiped
   all markers, putting every script in the must-go-online state → user hit it.
3. **Current: no markers at all.** Always pass `--offline`. On rc 101, a
   build-only probe (`cargo build -Zscript --offline --manifest-path`, stderr
   captured) disambiguates:
   - probe succeeds → the 101 was the program panicking → exit 101
   - probe fails, stderr mentions `offline` → one online `cargo build`, then offline run
   - probe fails otherwise → compile error, already streamed by the run attempt → exit 101
   Plus: toolchain now has a GC root (`nix build -o ~/.cargo/target/.rust-toolchain`)
   so the GitHub flake eval can't come back after `nix-collect-garbage`.

## Verified (all under `unshare -rn` = zero network)
- daily script (bluetooth) → rc 0
- never-built script w/ cached deps → rc 0
- compile error → printed exactly once, rc 101, no network attempt
- panic → printed once, rc 101
- uncached dep offline → clean resolution error (nothing can fix this case)
- uncached dep online (tinyjson) → fetched once, ran; offline forever after

## Known remaining gaps / where to look if it breaks again
- Network is still required exactly once per never-downloaded dep version.
  If that's still too much: vendor crates or pre-warm cache on rebuild
  (`cargo fetch` for each script as a home-manager activation step).
- The fetch case first streams a scary offline-resolution error before silently
  retrying online and succeeding. Cosmetic; suppressing it would require
  capturing the run's stderr (breaks tty). Left as is.
- Probe's `grep -q offline` false-positives if a compile error's source snippet
  contains "offline" → harmless spurious online build, error printed twice.
- `sudo <script>` creates root-owned target dirs; wrapper has
  try_fix_root_owned_dirs for that (pre-existing).
- If offline failures reappear, first check: does stderr show a crates.io URL
  (cargo went online = wrapper regression) or a github flake unpack (toolchain
  GC root `~/.cargo/target/.rust-toolchain` missing)?
- Registry cache GC: if something prunes `~/.cargo/registry`, all deps become
  "never downloaded" again. Wrapper handles it (goes online once), but offline
  you're stuck until network.

## Repro / test harness
```bash
unshare -rn <script> args...   # run with no network, as fake-root
# note: inside unshare -rn, id -u = 0, so try_fix_root_owned_dirs is skipped
```
