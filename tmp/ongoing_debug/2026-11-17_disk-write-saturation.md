# /home NVMe saturated by builds — editor saves stall

## Problem
`:w` in nvim takes 150–680 ms, so typst `:Watch` previews lag. Not typst (incremental compile 37–49 ms), not the typst.vim fork, not save hooks (`noautocmd write` equally slow).
Cause: `fsync` on /home (ext4, nvme0) waits behind parallel cargo builds; undo-file fsync measured 344 ms, bare `dd conv=fsync` of 8 KB 0.16–0.44 s.

## Constraints (from the user)
- losing the last 5–10 min of work on a whole-machine crash is fine; **random/old files corrupting is not**
- `~/s` is ~800 GB; it does not fit on the 465 GB Windows partition as a whole
- kache stays (saves ~9 h compile/day); anything that duplicates its store across filesystems must be justified by numbers
- measurements must not add load to the saturated drive: counters, procfs, bpf, fatrace only; no `du`/`dust` scans

## Hardware
| | nvme0 (/home) | nvme1 (/) |
|---|---|---|
| model | UMIS RPJYJ1T24MML1AWY (Lenovo OEM) | Kingston SNV3S1000G (NV3) |
| DRAM | none (HMB 64 MB) | none (HMB 64 MB) |
| wear / written | 30% / 82.5 TB | 6% / 20.2 TB |
| temps | Composite 68, Sensor 2 (controller) 87 °C; fw warn/crit 79.85/82.85 on Composite | Composite 49, Sensor 1 76 °C; fw 74.85/79.85 |
| thermal throttle | T1 18 transitions, total time 0 | — |

Partitions: nvme0 = p1 /boot 428M, p3 /home ext4 921G (654 used), p5 swap 32G. nvme1 = p1 MSR 16M, p2 NTFS Windows 465G (user is fine nuking it), p3 / ext4 466G (323 used, 112 free; holds /nix), p4 WINEFI 478M.
/home: ext4, `data=ordered`, `commit=5`, delalloc, **no fast_commit**. Schedulers: `none` on both. fstrim weekly trims ~160 GB from /home (churn proxy).

## Measurements
### Latency per drive (15 s /proc/diskstats sample, under load)
| | write MB/s | write-ms/s (≈ requests in flight) | ms of wait per MB |
|---|---|---|---|
| nvme0 /home | 51 | 57 694 | ~1100 |
| nvme1 / | 77 | 10 705 | ~140 |
The Kingston does more bytes at ~8× less wait. PSI io on that sample: some 55%, full 41% (avg10).

### Who writes (this boot, 3.2 h uptime)
cgroup io.stat, actual block writes:
- nvme0 (/home): **364 GB**, essentially all `user@1000.service` (io controller not delegated below it, so no finer split from cgroups)
- nvme1 (/): nix-daemon 58 GB, journald 5 GB

/proc/<pid>/io write_bytes, which includes reaped descendants (so a Claude session = its cargo/rustc children):
| GB | family |
|---|---|
| 186 | systemd --user (reaped orphans: kache daemons, killed builds) |
| 184 | Claude sessions → their cargo/rustc/kache children |
| 61 | nix-daemon (nvme1) |
| 33 | cargo/rustc/kache alive at sample time |
| 13 | fish (user-run builds) |
| 2.9 / 2.6 / 1.5 / 0.8 | browsers / tg / docker / LSPs |
→ Rust ≈ 95%+ of /home writes; everything non-Rust < 10 GB (~2–3%).
Per-session (site_conductor 58+45+12+1.5, v_flakes 50, playbook 9, debouchage 4.6 GB): `~/s/ev/_sa` ≈ 130 of 184 GB.

### What the bytes are — heavy window (bpftrace, 60 s, /home only)
Probes: fexit `vfs_write`/`vfs_writev` (retval), fentry `ext4:ext4_page_mkwrite` (×4096, mmap-writing linkers), fexit `vfs_copy_file_range` (retval; Rust `std::fs::copy` goes through it and never hits `vfs_write`). Keyed by comm + last 4 path components.
Block writes to nvme0 in the same window: **3 111 MB** (52 MB/s); traced: 1 995 MB (rest: journal/metadata, pages dirtied before the window).
| MB | % of traced | what |
|---|---|---|
| 570 | 29 | **kache ingest**: copying fresh outputs into `store/staging` |
| 537 | 27 | linker outputs (test binaries, bins, proc-macro `.so`) |
| 320 | 16 | rustc rlib/rmeta/objects in deps/ |
| 205 | 10 | **kache restore**: `.kache-prestage-*` copies into target/ |
| 196 | 10 | C build-script toolchain (ar/as/cc), e.g. onig_sys |
| 69 | 3 | kache index.db + WAL + events |
| ~100 | 5 | other (tg, browsers' cache threads, node/bun, git) |
→ **kache ≈ 43% of traced bytes; it adds ~+80% on top of what the build itself writes** (~1 050 MB).
A light window (5.4 MB/s, before adding the copy_file_range probe) showed rustc rlib/rmeta at 55% and kache at ~7% — the kache cost scales with build/miss activity and is invisible without the copy_file_range probe.
Pitfalls hit:
- a `fatrace` close-write + `st_size` tally counts SQLite/jsonl files at full size (made kache's index look like 1.1 GB/30 s)
- `vfs_write` alone misses `copy_file_range` (all of kache's copies) and mmap writes (linker outputs)

### kache — from its own per-compile event log (`~/.cache/kache/events.jsonl` + `.archive/*.zst`)
Never trust `kache stats` summaries: `time_saved` sums original compile times of restored units (overstates wall clock, cargo is parallel) and `copied_bytes` counts restores only. The event log has per-compile byte accounting (`store_copied_bytes`, `store_hardlinked_bytes`, `copied_bytes`, `hardlinked_bytes`, `restore_copy_exclusive_bytes`, `passthrough_reason`).
Window 2026-11-17 15:42–18:54 UTC (the 364 GB block-write window):
| | events | ingest copy | ingest link | restore copy | restore link |
|---|---|---|---|---|---|
| own bins/test binaries (≥40 MB) | 252 miss / 26 hit | **20.8 GB** | 1.4 | 1.8 | 0.8 |
| external deps | **9 202 miss / 4 349 hit** | 11.9 | 11.5 | 9.1 | 3.6 |
| own lib crates | 4 556 miss / 2 241 hit | 1.1 | 0.5 | 0.2 | 0.3 |
| build scripts | 1 770 miss / 813 hit | 2.6 | 0 | 1.8 | 1.0 |
→ kache copies 49.4 GB = **~14% of block writes** (ingest 36.4, restore 13.0). Heavy 60 s bursts: ~43%.
Index (`index.db`, read with `sqlite3 -readonly`): **46 746 of 71 155 entries (109 GB, 69% of the store) were never hit once** — pure ingest writes.
Why external deps miss: key splits across repos, not features alone. tokio: 107 entries; 26 with identical rustc + profile + feature set, different keys. cfg_if (no deps): 100 entries. Splitters found:
- 7 distinct `.cargo/config.toml` shapes across 79 repos; **31 still had the legacy `target.x86_64-unknown-linux-gnu.rustflags` array beside the cfg string** → cargo joins both → doubled flags (+ `web_sys_unstable_apis` in some) → different keys. Fixed in v_flakes v1.6.249 (merge retracts it).
- `split-debuginfo` present in some repos, not others (old v_flakes pins).
- two nightlies in the store: 1.98 (142 GB) and 1.100 (14 GB).
- per-repo `[profile]` overrides, different dep versions in each Cargo.lock.
Next diagnostic: `explain_miss = true` briefly, then `kache explain <crate>` gives per-dependency digests.
Policy facts (docs `deduplication.mdx`, source `crates/kache-store/src/{store,link}.rs`, `src/args.rs`):
- `cache_executables` gates `is_user_facing_executable()` = `--test` or crate-type `bin` → own bins, test binaries **and build scripts** (crate-type bin). Measured with it off: dep build-script *runs* still hit (12/13 in a fresh target dir) — run cache keys the deterministic binary content.
- ingest: reflink → hardlink for immutable kinds (`.rlib`, objects, Linux proc-macros/build-script bins) → byte copy (executables, `.rmeta`, C objects).
- restore: only one target dir may hardlink a blob; later ones copy ("exclusive" copies: 7.1 GB in the window, ~2%). `shared_hardlink_restores = true` lifts it, but a restore re-stamps mtime on the shared inode → other trees' dependents look stale (#794). Not worth ~2% when XFS reflink removes the same bytes safely.
- `build_script_hermetic`: shares a build script's OUT_DIR across target dirs (applies to all build scripts incl. deps). Not evaluated.
- `kache doctor`: hardlink build-tree → store works on this layout; the copies are policy, not EXDEV.
### cargo
`build.build-dir = "/abs/{workspace-path-hash}"` works on our nightly (tested): intermediates go there, only the final binary is copied into the repo's `target/`. Lets build I/O move without moving repos.

## Rejected
- **typst.vim fork** — typst path is unchanged `typst watch`; not the cause.
- **nvim `fsync=false`** — hides the stall for saves only; builds stay saturated.
- **ext4 `data=writeback`** — same bytes, only reordered; fixes fsync entanglement (ATC'17: ordered p95 >3.5 s vs <0.2 s under 400 MB/s background) but can't be scoped to `~/s` while it's part of /home. Acceptable only on a separate `~/s`-like fs.
- **ext4 `fast_commit`** — ~2.8× lower fsync latency (ATC'24), but its crash-replay path keeps producing corruption bugs that can hit *any* file (CVE-2024-26601 bitmap, Aug 2026 half-applied replay, Jan 2026 Arch power-cut report). Violates the "no random corruption" constraint.
- **no journal / nobarrier** — same violation.
- **I/O priority (BFQ + idle class)** — buffered writes are flushed by kworkers, so the process ioprio mostly doesn't apply.
- **btrfs** for builds — slower than ext4/XFS on Phoronix 6.15/7.0, regressions through 7.0.
- **kache store on its own btrfs partition shared across disks** — reflink/hardlink only work within one fs, so every ingest and restore becomes a copy.
- **moving all of `~/s`** to nvme1p2 — ~800 GB doesn't fit 465 GB; and just relocates the whole load.

## Done
- **v_flakes v1.6.248**: generated `.cargo/config.toml` gets `[env] KACHE_CACHE_EXECUTABLES = "false"` (cargo passes `[env]` to the rustc wrapper; verified: `passthrough … user-facing executable (cache_executables=false)`). Rolled into gaussian_pivot (committed) and site_conductor (working tree only — commit blocked by another agent's broken `crates/placement_overlay` manifest). Expected: −20.8 GB ingest per 3.2 h window (~6% of writes).
- **v_flakes v1.6.249**: merge retracts legacy `target.<triple>.rustflags` arrays → repos converge on one rustflags string as they bump.
- eww: kache hit rate (last hour, events log tail, 0.09 s / 60 s).

## Promising
1. **XFS (reflink) for builds + kache store** — every kache copy becomes a clone: ~14% of writes (49 GB / 3.2 h), more in bursts. XFS is per filesystem: it can't be enabled for a directory, so it needs its own partition.
   Sizes (2026-11-18, idle `du`): /home used 582 GB = `~/s` 315 (of which target dirs ~200–250) + `.cache` 94 (kache store) + ~170 other. `~/s` without targets ≈ 65–100 GB.
   - **B (preferred):** wipe Windows nvme1p2 (465 GB) → XFS, mount at `/home/v/s`, kache `local_store` inside it. Builds move to the Kingston (8× lower wait, 6% wear) beside nix; /home stays untouched on the UMIS with only the editor/notes load. No /home reformat or copy.
   - A (user's first idea): move /home minus `~/s` (≈ 268 GB) to nvme1p2, reformat nvme0p3 as XFS for `~/s`. Same isolation, but reformats and copies all of /home, and keeps builds on the worn, slower UMIS.
   Migration B: `rsync -aHAX --exclude target/` `~/s` → new fs (targets rebuild from kache) ; stop builds/agents; final rsync; `mv ~/s ~/s.old`; `fileSystems."/home/v/s"` (xfs, noatime) + kache `cache.local_store`; `nixos-rebuild switch`; verify; drop `~/s.old`. Kache starts empty (refills within a day). Windows boot entries (WINEFI nvme1p4) go too.
2. **Unify kache keys across repos**: bump repos to v1.6.249 (one rustflags string, split-debuginfo everywhere), one nightly. Measure external-dep hit rate before/after with the eww widget + events log.
3. **Cut build bytes at the source**: linker outputs 27% (test binary count — separate agent), aws-lc-sys (separate agent: codestyle `no-aws-lc` lint + ev_lib/panel/site_conductor PRs).
4. `build.build-dir` on nvme1 — superseded by option B.

## Open
- Which repos produced the heavy-window linker bytes: raw per-file trace wasn't kept (only aggregates). Active then: site_conductor (3 sessions + worktree code-mode), sites/panel worktree one-source, playbook, sites/debouchage, v_flakes, /tmp/btc_line_ganttdemo. Keep the raw `@w` map next time.
- Heavy-load bpf trace including mmap-written files (linker outputs): what share are linked binaries really?
- Whether kache hit latency (5.4 s avg) is disk-bound restores or scheduler wait.
- Cross-repo vs same-repo share of kache hits (stats don't split by repo).
- `~/s/ev/_sa` size (no scan done; measure with ionice idle when builds are quiet).

## Measuring (adds no disk load)
Per-file write bytes on /home; `271581191` = kernel dev of `mountpoint -d /home` (259:7 → `259<<20|7`). Run `nix shell nixpkgs#bpftrace -c sh -c 'sudo timeout -s INT 60 $(command -v bpftrace) trace.bt'`, compare against `/proc/diskstats` field 10 (sectors written) over the same window.
```
fexit:vmlinux:vfs_write, fexit:vmlinux:vfs_writev {
  $d = args->file->f_path.dentry;
  if ($d->d_sb->s_dev == 271581191 && retval > 0) {
    @w[comm, str($d->d_parent->d_parent->d_parent->d_name.name), str($d->d_parent->d_parent->d_name.name), str($d->d_parent->d_name.name), str($d->d_name.name)] = sum(retval);
  }
}
fentry:ext4:ext4_page_mkwrite {
  $d = args->vmf->vma->vm_file->f_path.dentry;
  if ($d->d_sb->s_dev == 271581191) {
    @w[comm, str($d->d_parent->d_parent->d_parent->d_name.name), str($d->d_parent->d_parent->d_name.name), str($d->d_parent->d_name.name), str($d->d_name.name)] = sum(4096);
  }
}
fexit:vmlinux:vfs_copy_file_range {
  $d = args->file_out->f_path.dentry;
  if ($d->d_sb->s_dev == 271581191 && retval > 0) {
    @c[comm, str($d->d_parent->d_parent->d_parent->d_name.name), str($d->d_parent->d_parent->d_name.name), str($d->d_parent->d_name.name), str($d->d_name.name)] = sum(retval);
  }
}
```
Other cheap sources: `/sys/fs/cgroup/**/io.stat` (per-device wbytes; not delegated below `user@1000.service`), `/proc/<pid>/io` write_bytes (includes reaped children), `kache stats --json`, `/proc/pressure/io`.

## Phantom io% in eww (2026-11-17, post-reboot)
`io48%` with an idle drive (diskstats io_ticks 40 ms/5 s, no D-state tasks) was **ringboard-server** parked in `io_cqring_wait`: io_uring waits count as iowait, so PSI `some` reads ~46% permanently. Proved by A/B: ringboard stopped → +2 ms stall/5 s; running → +2.3 s/5 s. Global `/proc/pressure/io` (the eww poll) cannot exclude one cgroup; `io%` is useless while ringboard runs. Real build-time saturation above is separate and still true.
Open: use IORING_ENTER_NO_IOWAIT upstream (ringboard), or make the eww poll read per-cgroup/diskstats queue depth instead of global PSI.
