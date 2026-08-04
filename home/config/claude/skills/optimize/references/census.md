# /optimize reference: the census

Load this in Step 2. Five classes, run all five. Record every hit as `file:line` and evaluate nothing yet — mixing search with judgement is how you stop searching after the first interesting thing.

**Scope the greps to the paths the volume model (Step 1) marked hot.** A `Vec::new()` in a CLI argument parser is not a finding; the identical line in a per-message decoder is the top of the report. Without the volume model the census returns hundreds of hits and is useless. With it, it returns a dozen.

**Negative results are results.** Write down the classes that came back clean. Class 2 coming back empty is the most valuable single sentence a survey can contain.

---

## 1. Allocation in a per-item path

Highest hit rate of the five, and the class that produced the largest real win in the run this skill was distilled from: a `String` allocated per parsed number, at 800 numbers per message and millions of messages per file — ~10⁸ short-lived allocations per day of data, purely to shift a decimal point.

```bash
rg -n 'String::(new|with_capacity|from)|to_owned\(\)|to_string\(\)|format!|\.to_vec\(\)|Vec::new\(\)|vec!\[|Box::new|\.clone\(\)|\.collect\(\)' <hot-paths>
```

Then, per hit, three questions — all three must be answered in the report entry:

- **How often does it run?** From the volume table. Below ~10⁴/run, drop it.
- **Does the value escape?** If it is dropped in the same iteration, it should be caller-owned scratch reused across iterations, or not exist.
- **Is its size known?** A `Vec` of compile-time-constant length is an array wearing an allocation (`scalarize`). A `Vec` whose final length was *already computed elsewhere in the same function* is a missing `with_capacity` (`capscale`) — and that one is nearly free to fix.

Specific shapes that recur:

| Shape | Fix |
|---|---|
| `.lines()` over a reader | `read_line` into one reused buffer + `clear()` |
| a formatting round-trip to parse (`format!` → `str::parse`) | parse the digits directly; usually also a **correctness** win, see class 3 |
| a DOM parse (`serde_json::Value`, `ElementTree`) read once by key | a borrowed `#[derive(Deserialize)]` struct with `#[serde(borrow)]` |
| a temporary collection immediately consumed | fuse into the iterator chain (`fuse`, row 13) |

Other languages: `rg -n 'new |make\(|append\(' ` (Go — plus `go build -gcflags=-m` for escape analysis, which is authoritative and free); `rg -n 'std::(string|vector|make_shared|make_unique)'` (C++); for Python the class is object churn, use `tracemalloc`.

## 2. Indirection at the hot loop

The largest multiplier when present, and one grep.

```bash
rg -n 'Rc<|Arc<|RefCell|Mutex<|RwLock<|Box<dyn|&dyn |impl Fn|fn\(\)' <hot-paths>
```

Judge by **what reaches the innermost loop**, not by what exists in the crate. A `Box<dyn Trait>` created once per connection is fine; the same type dereferenced per message is the whole report.

- Present in per-item code ⇒ this outranks everything else. Fix order: remove the wrapper (`unbox`, row 20) > hoist the borrow out of the loop (`hoistborrows`, row 21) > replace `Box<dyn Fn>` with an enum (`defunctionalize`, row 7).
- Absent ⇒ **record it as a finding.** By the natural experiment in `cannot-see-through.md` you are structurally in the parity cohort, the representation work is already done, and the survey should redirect entirely to classes 1, 3 and 5. Knowing where *not* to look is worth as much as a hit.

C++: `shared_ptr` in a loop, virtual calls on a hot object, `std::function`. Go: interface-typed values in per-item code, and `-gcflags=-m` again.

## 3. Representation churn

Three sub-shapes, all invisible to the compiler because each changes a type.

**Rebuilt collections** — a collection constructed from data that already has the property the collection provides:

```bash
rg -n 'BTreeMap|HashMap|BTreeSet|HashSet|\.sort|\.collect::<.*Map' <hot-paths>
```

A `BTreeMap` built from an already-sorted sequence, then flattened back by its consumer, is an allocation plus an O(n log n) rebuild for ordering that was already there. Count the sites before ranking: if the same conversion appears at four boundaries, this is not a micro-optimization, it is **deleting a type**, and it ranks accordingly. Also check `densemap` (row 25): a map over a small dense integer key is a `Vec` indexed directly.

**Layout round-trips** — columnar source → per-item struct → columnar sink converts layout twice for nothing (`interleave`, row 19). Look wherever an SoA buffer meets a row-oriented API. The fix is usually a bulk `extend_from_slice`/`append_slice` that the sink already offers.

**Value round-trips — check these for correctness first.**

```bash
rg -n 'as f64|as f32|as i64|as i32|\.round\(\)|\.parse::<f' <hot-paths>
```

A value passing through a wider or lossier type and back is slower *and* often wrong. A nanosecond timestamp parsed as `f64` and multiplied by `1e9` sits at the edge of exact `f64` integer representation — that is a **correctness finding**, and it belongs above every performance item in the report. This class earns its place in the census on correctness yield alone.

Conversely, if the codebase already stores fixed-point `i32`/`u32` where `f64` was the obvious choice, that is `elemtype`/`narrow` **already banked** (row 22/26). Record it as a positive finding and do not let a later rewrite widen it back for convenience.

## 4. Fixed-size work on the heap

```bash
rg -n 'vec!\[.*;\s*[A-Z_]+\]|vec!\[.*;\s*\w+::LEN|with_capacity\(\s*[A-Z_]' <hot-paths>
```

A heap collection whose length is a compile-time constant (`scalarize`, row 17), or a buffer allocated per iteration that could be caller-owned scratch. Two tells worth grepping for directly:

- a function allocating a buffer, filling it, reading it, dropping it, called per item
- a **doc comment or existing code elsewhere in the same file that already makes this argument** and was not applied one level up. This happens more than it should, and it is free evidence that the fix is correct and wanted.

Where `[T; N]` is not spellable (an associated const without `generic_const_exprs`), the honest fix is a scratch buffer owned by the caller and threaded through, not an array.

## 5. Syscalls and I/O in a loop

The class with the worst constant factors, and often the easiest fix.

```bash
rg -n 'read_dir|metadata|File::(open|create)|fs::|\.flush\(\)|Command::new|reqwest|ureq' <hot-paths>
rg -n 'Compression|encode|compress|serialize' <hot-paths>
```

Four recurring shapes:

- **Re-enumeration** — a directory listed on every write, giving O(n²) syscalls over a run. Cache it, or exploit ordering so only the last entry needs checking.
- **Decode-then-filter** where the format supports **pushdown** — Parquet row-group statistics and row filters, index scans, range requests. Reading everything and discarding 99% is the most expensive possible way to answer the query, and the capability is usually already in the dependency tree.
- **Eager `collect()` of a streaming reader**, defeating streaming and buying a full-size allocation.
- **Compression on a latency-critical thread.** Synchronous ZSTD at a high level on the ingest thread is a multi-hundred-millisecond stall — for live data, a gap. Fix by lowering the level on the latency-sensitive path (a level-1/level-3 split by purpose) and moving the work to a dedicated writer thread. Note this is the one place a second thread reliably pays, and it is *not* a data-parallelism shape — do not reach for a work-stealing pool for it.

---

## On parallelism, before anyone suggests it

Check all four before proposing a parallel runtime:

1. **Is there a serial data dependency?** A tick-by-tick simulation, a fold, a stateful decoder — not parallelizable at any width, and no library changes that.
2. **Are the cores already busy?** If the deployment runs many independent jobs concurrently (a parameter sweep, a per-day batch, a request-per-core server), the machine is saturated and intra-job parallelism buys **nothing** while adding synchronization and non-determinism. This is the common case and it is routinely missed.
3. **Is there shared mutable state at the join?** A global registry, a catalog with a cross-item consistency check, an ordering constraint — the contended resource caps the speedup regardless of width.
4. **Is the path latency-critical and single-threaded by design?** Then it stays that way; say so and move on.

If all four are clear, the shape that survives is usually per-file/per-shard independent work at ingest — and even then, measure against the already-saturated baseline, not against a single-threaded one. The honest default answer to "should we add a parallel runtime" is **no**, with the reason stated.
