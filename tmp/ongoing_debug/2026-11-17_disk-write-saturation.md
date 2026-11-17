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

### kache (`kache stats --json`)
- store 123 GB on disk (146 GB logical), over its 100 GiB cap
- 24 h: hit rate 26% (weighted by compile time 19%), 15 227 hits / 37 111 misses, **time saved ≈ 8.9 h/day**
- since Nov 6 (11 d): restored by hardlink 60 GB, **by byte copy 266 GB** (ext4: no reflink), pruned automatically 932 GB (~85 GB/day churn)
- avg hit 5.4 s vs miss 19.2 s (hit_elapsed/hits) — slow for a restore; unclear if it includes permit wait
- `total_permit_wait_ms` ≈ 36 h summed over 24 h: the scheduler pacing compilers
- crosses filesystems silently: when hardlink fails with EXDEV, both ingest and restore become byte copies (`src/link_probe.rs`, `kache doctor` shows it). Store path: `cache.local_store`.
- the lifetime `copied_bytes` counter covers **restores only**; ingest copies are not in it, so it understates kache's writes badly (see heavy window: ingest 570 MB/min).
- ingest policy (`crates/kache-store/src/store.rs`, `link.rs`): reflink first; hardlink only for immutable kinds (`.rlib`, objects); **executables, dylibs, proc-macros, `.rmeta` are always byte-copied** on a non-CoW fs. Restores hardlink only for the first consumer of a blob; later consumers get private copies (#794, mtime stamping).
- `kache doctor`: "hardlink build-tree → <store>/staging works (reflinks unsupported on this filesystem)" — same-fs layout is fine; the copies are policy, not EXDEV.
- `cache.cache_executables` (bool) turns off caching bin/dylib/cdylib. On ext4, per binary of size N: miss = link N + ingest copy N, hit = restore copy N, uncached = link N. At 26% hit rate that's ~1.74N vs N → caching executables costs ~+74% writes on binaries to save link CPU on hits.

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

## Promising
1. **`cache.cache_executables = false`** (config only, `hosts/hm-shared/home.nix` kache block): removes the ingest copy of every linked binary/proc-macro and their restore copies; costs a relink on what would have been a hit. Not deployed: needs a home-manager switch, and the shared kache daemon must pick up the new config. Measure with the same bpf trace before/after.
2. **Reflink-capable fs (XFS) for builds + kache store**: every kache copy (ingest 570 + restore 205 MB/min in the heavy window) becomes a clone. Candidate: nvme1p2 (Windows, 465 GB) as XFS holding `~/s/ev/_sa` (≈ 70% of Rust writes) **and** the kache store; the rest of `~/s` crosses the fs boundary → EXDEV → copies (today most of those are copies anyway, except rlib/object hardlinks).
   - XFS: fastest on Phoronix Linux 7.0 and 6.15 geomean, metadata-only journal (crash = recent writes only, git covers).
3. **Cut build bytes at the source**: linker outputs 27% (each integration test is its own linked binary — fewer test binaries), C build scripts 10% (onig_sys etc. rebuilt per target dir), `debug = false` for non-workspace deps.
4. `build.build-dir` on nvme1 for the remaining workspaces if space allows (112 GB free on / — tight).

## Open
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
