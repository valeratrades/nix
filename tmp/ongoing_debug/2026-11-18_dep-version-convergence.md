# External deps miss kache because repos resolve different versions

## Problem
External (crates.io) deps miss kache more often than they hit: 37 853 misses vs 28 758 hits (43%) in the 27.8 h event log (2026-11-16 21:36 → 11-18 01:22). The misses cost 1 681 CPU-min of compile time. A crate's key includes the content of its `--extern` deps and cargo's `-C metadata`, and both carry the exact versions of the whole dependency closure. So when two repos pick different patch versions of one leaf crate, every crate above that leaf gets a different key.
Background: `2026-11-17_disk-write-saturation.md`.

## Measured
Sources: 75 `Cargo.lock` files (no `tmp/`, no test fixtures). "Active" means the 30 repos with the most kache events in the window. Event log: `key_fields` per compile. Index: `entries`.

### Spread (all lockfiles)
- 2 168 registry crates. 1 052 of them have ≥2 versions in use. There are 2 910 extra versions; **70% of those are semver-compatible** (`cargo update` would merge them) and 30% are different majors (syn 1/2/3, thiserror 1/2, getrandom 0.1–0.4, zerocopy 0.7/0.8).
- Locks are *recently committed* (most active repos have commits dated 11-17 or 11-18), but they are **not up to date**. Cargo re-resolves only what a `Cargo.toml` change requires, so each repo keeps the patch versions from its last full `cargo update`. Example (active repos): syn 2.0.117/118/119, tokio 1.52.3/1.53.1/1.54.1, libc .186/.189/.191, zerocopy .52/.54/.55/.57/.59/.63. The pattern is several versions per crate, from repos updated in different weeks. No single repo is far behind.

### Why the external misses happen (event log, each miss compared with the closest earlier key for the same crate under the same kache version)
| CPU-min | share | fields that differ | reading |
|---|---|---|---|
| 805 | 48% | args+externs | same crate sources, but different deps (dep versions or dep features) and/or flags |
| 152 | 9% | args | features / rustflags (the legacy rustflags split, fixed in v1.6.249) |
| 158 | 9% | identical key seen earlier | eviction or concurrency; not versions |
| 120+28 | 9% | +sources | the crate's own version differs |
| 87 | 5% | first sighting | |
| rest | ~20% | compiler, lints, diagnostics, link mixes | toolchains, lint flags |

### Simulation: closure identity per (crate, closure of dep versions), from the lockfiles
Converged = every crate set to the fleet-max version within its semver band. Target-only crates (windows*, wasm*, mac) are excluded. Lockfile dependency lists include optional deps, so the leftover splits after convergence come from **features**.
| scope | distinct units now | after convergence | 1 per major (floor) | compile-time-weighted reduction |
|---|---|---|---|---|
| 30 active repos | 6 847 | 4 146 | 2 036 | **−39%** |
| all 75 repos | 11 612 | 6 638 | 2 922 | −44% |

### Top splitters (active repos, closures now → converged, average compile time)
```
syn 22→3 (11.3s)   darling_core 25→5 (8.6s)   zerocopy 15→2 (11.0s)   serde_derive 13→2 (11.2s)
insta 21→10 (10.5) thiserror-impl 22→3 (5.6)  bon-macros 13→3 (10.2)  zerocopy-derive 15→2 (7.6)
futures-util 21→7  derive_more-impl 13→4      combine 19→5            rustix 22→7
v_utils_macros 17→4 (our own crate!)          rand 36→8               facet-macros-impl 9→3
serde_core 13→2    openssl-sys 11→5           regex-automata 8→1      pest_meta 9→3   cc 17→5   clap_derive 14→2
```
The root causes are the proc-macro stack (proc-macro2 has 10 versions, quote 11, syn 21, unicode-ident 10) and the leaf crates (libc 15, cc 28, memchr 8). Every derive macro sits above them, so each version difference at the bottom multiplies upward.
Tokio in the whole fleet: 59 closures now, **38 after convergence**. Tokio is split mainly by feature sets, not by versions.

### A splitter we did not know about: two kache versions running at once
- 39% of events in the window came from **kache 2.0.0 (key schema 33)** and the rest from 2.1.1 (schema 34). Both write to one store and their keys can never match, so every crate is split in two.
- 2.0.0 is still running now (last event 01:23), in panel `worktrees/no-aws-lc`, codestyle and ev/skills. The cause: `v_flakes/tools/kache.nix` pins the kache version, and each repo's devShell gets kache from **its own `flake.lock` v_flakes pin**. A repo on an older pin runs an older kache. The same thing will happen at every kache bump.
- The index holds 28 919 schema-33 entries (**81 GB**). 2.1.1 can never hit them; they stay useful only while some repo still runs 2.0.0.

## kache side
- The docs (`docs/how-it-works/cache-key.mdx`, `configuration.mdx`) have no option that normalizes dependency versions. The key options are `key_salt`, `key_env_vars`, `path_only_env_vars`, `base_dirs`, `extra_inputs`, and all of them only add inputs or normalize paths.
- Ignoring dependency versions would also be **unsound**. The key hashes the `--extern` rmeta/rlib *content*, and that content contains each dep's SVH and StableCrateId (from `-C metadata` = name + version + dep metadata). Symbol mangling uses those values too, so a different dep version gives different output bytes.
- Result: the fix has to come from convergence on our side. kache can only stop splitting itself (one version on the machine).

## Options (ranked)
1. **One kache per machine, not per repo.** The devShell stops shipping kache and uses the home-manager kache on PATH. CI keeps its own copy (nix-env-action). This removes the 2.0/2.1 split now and at every later bump.
   Trade-offs: the devShell no longer controls the kache version, so a repo can't pin an older kache (nobody wants that). CI and local can run different versions, which is harmless because CI has its own store.
2. **Synchronized fleet `cargo update`.** One systemd user timer, weekly, at night. It runs `cargo update` in every repo one after another (all within minutes, so all see the same crates.io state) and commits only `Cargo.lock` (`git commit -- Cargo.lock`). It skips a repo whose `Cargo.lock` is dirty.
   - Expected effect: −39% distinct external units (simulation). Each new version set is compiled once by the first repo and then hit by the rest. The store has one full churn per week instead of continuous drift.
   - Doing it *at the same moment* is what makes it work. Updating often at different moments (shellHook, pre-commit) gives each repo whatever was newest at its own moment, which is today's situation. **Reject running `cargo update` from the shellHook or pre-commit.**
   - Risks: a semver-compatible update can still break a build (rare); the timer runs no builds, so CI catches breakage. Agents work during the day: night timing plus committing only the lock file limits conflicts. Existing worktree branches stay on the old versions until they rebase.
   - Cadence: weekly. Daily would give 7 store churns per week. Patch releases of syn, libc and cc are roughly weekly anyway.
3. **Fleet snapshot plus lazy convergence** (a refinement of 2, for repos the timer skipped: dirty locks, new repos, worktrees). The timer also writes `~/.local/state/fleet-lock.json` (the max version per (crate, band) for the top ~50 heavy crates). A small step in the v_flakes shellHook runs `cargo update -p <crate>@<old> --precise <snap>` only for crates where the lock lags the snapshot in the same band. Cost: ~0.5 s per drifted crate, and nothing when the repo is in sync. The snapshot is machine-local, as the kache store is, so v_flakes needs no weekly releases.
   Trade-off: more moving parts than 2. It is only worth adding if the timer's skip rate turns out high.
4. **Feature unification (the next lever after versions).** The floor goes from 4 146 to 2 036 units, and tokio stays at 38 closures. A published `fleet_hack` crate (one per machine, depending on heavy crates with union features such as tokio `full`, serde `derive`, syn `full`) that every repo depends on would make the feature sets equal.
   Trade-offs: small repos compile more crates, but those come from the cache; it adds dependencies nobody asked for; it couples all repos. Not before 1 and 2 are measured.
   `cargo-hakari` unifies features *inside* one workspace only, not across repos. **Reject** it for this problem.
5. **Our own published crates** (v_utils_macros has 17 closures, v_utils, ev_lib). Different repos pin different releases, and each release pulls its own tree. These versions converge with option 2 only if the requirements allow it (no `=` pins). Check after option 2 runs.
6. **codestyle lint "lock lags fleet snapshot"**: only useful together with 3, as `--fix` that applies the snapshot. As a warning alone, nobody acts on it.
7. **eww indicator.** "A dep in >5 versions across active repos" is noise: in the active set, a heavy crate has 2–4 compatible versions, and the damage comes from the product over the closure, not from one crate. Signals you can act on:
   - `kache: N` = the number of distinct kache versions in the last hour of events (`version` field). Alert when N>1. It is cheap and points to one fix (bump the pin, or option 1).
   - `drift: K` = the number of repos active in the last hour (`root`) whose lock differs from the fleet snapshot (needs 3). Click to converge them.
   Do not show raw version counts.
8. Out of scope here but seen in the data: 9% of misses had a key that existed earlier (eviction or concurrency); `kache gc` of schema 33 frees 81 GB once no repo runs 2.0.0.

```
             misses on external deps (100% = 1681 CPU-min / 27.8 h)
 ┌──────────────────────────────────────────────────────────────┐
 │ args+externs 48% ── dep versions ── opt 2/3 ──┐               │
 │                   └ dep features ─── opt 4    │ −39% units     │
 │ +sources 9%   ── own version ─────── opt 2/3 ─┘               │
 │ args 9%       ── rustflags/features ─ v1.6.249 / opt 4         │
 │ schema 33/34 split (39% of events) ── opt 1 (orthogonal)       │
 │ seen-key 9%   ── eviction/concurrency (separate)               │
 └──────────────────────────────────────────────────────────────┘
```

## Expected payoff
- Version convergence (2): external misses −30…40% → the external hit rate goes from 43% to **~60–65%**. That saves ~500–650 CPU-min/day, and external ingest copies drop by ~4–5 GB per 3.2 h window (~1.5% of block writes; the large write savings are kache's own-binary ingest and XFS, see the disk doc).
- One kache version (1): this split is separate from versions. While it lasts, every unit that both versions build is compiled twice. It brings another ~1.3× on the hit rate as long as old pins are around (an upper bound, because not every unit is built by both sides).
- Feature unification (4) would bring the remaining 4 146 units toward ~2 000, roughly another −30%. Decide after measuring 1 and 2.
- Method used to measure before and after: the classification above (`key_fields` diff per miss) and the external hit rate from `events.jsonl`, run on a window of equal length.

## Recommendation
Do 1 now (it is small, in v_flakes). Then do 2, the weekly synchronized `cargo update` timer. Add the eww `kache: N` alert. Add 3 and the drift indicator only if many repos are skipped. Look at 4 only after measuring.

## Caveats
- The simulation uses the lockfiles' dependency lists, which include optional deps and so overstate the closures. It treats every active repo as equally weighted.
- `args` mixes features, flags and `-C metadata`, so the version and feature shares inside "args+externs" are not separated. Turning on `explain_miss` would separate them.
- The scratchpad scripts (spread.py, miss.py, sim.py) are in the session scratchpad and are not saved.
