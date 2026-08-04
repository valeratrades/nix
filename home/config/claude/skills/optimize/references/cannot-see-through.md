# /optimize reference: the taxonomy — what a compiler cannot see through

Load this in Step 2 and read your code against it. It is the checklist that turns "look for slow things" into a finite search.

## Provenance

This is the 40-optimization registry of the **LOGOS** compiler (logicaffeine), distilled and re-verdicted for hand-written systems code. Source of truth: `crates/logicaffeine_language/src/optimization.rs` — a `static REGISTRY: &[OptMeta; 40]` carrying `keyword`, `label`, `group`, `cost`, `mem_class`, `requires`/`conflicts`/`preempts` per entry. The public benchmarks page does *not* contain the list; it is rendered client-side from that registry. Go to the generating source, not the rendered artifact.

Why a compiler's optimization list is the right checklist for hand-written code: it is an exhaustive, adversarially-tested enumeration of *every transformation someone found worth implementing*, each with a cost class and a dependency graph. Nothing else available is both that complete and that honest about what does not pay.

## The thesis (read this even if you skip the table)

From the LOGOS authors' own post-mortem after auditing generated assembly across 32 benchmarks:

> largo should never compete with LLVM on classical-optimization work […] and should spend all its effort on what LLVM *cannot see through*: the `Rc<RefCell<Vec>>` wrapper, allocation strategy, and semantic facts.

Their evidence is a natural experiment, and it is the single most useful number in this reference:

| What reached the hot loop | Result vs C |
|---|---|
| a plain slice `&[T]` | **0.98 – 1.11×** |
| a per-access `RefCell` borrow | **1.5 – 4.6×** |

Same source language, same optimizer, same LLVM. The *type at the hot loop* was the entire difference. Inverted for hand-written code: **your representation choices at the innermost loop dominate everything you can do to the loop body.** Optimizing a loop body that dereferences through indirection is polishing the wrong thing.

Three consequences worth stating flatly:

1. If indirection reaches your hot loop, that is the finding — nothing else in the function matters until it is gone.
2. If it does not, you are structurally in the parity cohort already, and the remaining costs are **allocation** and **I/O strategy**, which live at the program's edges (parse, serialize, flush) rather than in its core.
3. Establishing which of those two worlds you are in is the highest-information thing you can do early. It is one grep.

## The 40, grouped, with a hand-written-code verdict

`cost` is LOGOS's own implementation-cost class. **Verdict** is what it means for you:

- **compiler's** — LLVM/GCC do this; proposing it by hand is a false finding. See `llvm-already.md`.
- **YOURS** — the compiler cannot do it, because it requires a semantic fact or a representation change the compiler is not permitted to make. **These are the findings.**
- **design-time** — a decision made when the type was declared. Check whether it is already banked (a positive finding worth recording) and defend it against being undone.
- **n/a** — only meaningful to a compiler implementer.

### Inlining & calls (0–8)

| # | keyword | label | cost | verdict |
|---|---|---|---|---|
| 0 | `memo` | Memoization | Cheap | **YOURS** — only you know the function is pure and the domain is small. Changes complexity class; see the tripwire in `measurement.md`. |
| 1 | `tco` | Tail-call optimization | Cheap | compiler's, mostly — but LLVM does *not* guarantee it. If you rely on it for stack safety, restructure to a loop rather than hope. |
| 2 | `peephole` | Peephole rewrites | Cheap | compiler's. |
| 3 | `specialize` | Partial evaluation | Medium | **YOURS** in the generics sense — monomorphization *is* this, and a `dyn` boundary is you declining it. |
| 4 | `comptime` | Compile-time evaluation (CTFE) | Medium | **YOURS** — `const fn`, const generics, build-time tables. Also a trap: a runtime library forced onto a `const fn` site is a regression. |
| 5 | `inline` | Function inlining | Cheap | compiler's. **The most common false finding.** |
| 6 | `unfold` | Recursion unrolling | Heavy | compiler's. |
| 7 | `defunctionalize` | Defunctionalization | Cheap | **YOURS** — replacing a `Box<dyn Fn>` with an enum. Same family as `unbox` below. |
| 8 | `borrow` | Borrow inference | Cheap | **design-time** — in Rust the borrow checker forces you to have already decided. Take `&[T]`, not `Vec<T>`. |

### Loops (9–16)

| # | keyword | label | cost | verdict |
|---|---|---|---|---|
| 9 | `loophoist` | Loop-invariant code motion | Medium | compiler's — *unless* the invariant is behind a call it cannot prove pure (I/O, an allocation, a lock). Then **YOURS**, and that is exactly the "directory re-listed per write" shape. |
| 10 | `unroll` | Loop unrolling | Heavy | compiler's. |
| 11 | `loopsplit` | Loop index-set splitting | Cheap | compiler's. |
| 12 | `closedform` | Closed-form loop recognition | Medium | **YOURS** — the compiler will not discover a summation identity. Rare, enormous when it hits. |
| 13 | `fuse` | Deforestation / stream fusion | Medium | **YOURS** — every `.collect()` into a temporary that is immediately consumed is an unfused stage. Iterator chains fuse; a `collect()` in the middle is a wall you built. |
| 14 | `loopcse` | Loop-carried CSE | Medium | compiler's. |
| 15 | `cse` | CSE / GVN | Medium | compiler's. |
| 16 | `deadcode` | Dead-code elimination | Cheap | compiler's. |

### Arrays & memory (17–21) — **the highest-yield group**

| # | keyword | label | cost | verdict |
|---|---|---|---|---|
| 17 | `scalarize` | Array scalarization (SROA) | Heavy | **YOURS** — a heap collection whose length is a compile-time constant is an array wearing an allocation. Fix: array, or caller-owned scratch threaded through. This alone accounted for their worst non-indirection loss (3.70×). |
| 18 | `affine` | Affine array → closed form | Medium | **YOURS**, rare — an array only ever read at an affine index of the loop counter needs no array. |
| 19 | `interleave` | Array-of-structs interleaving | Heavy | **YOURS** — layout. Watch for the *round trip*: SoA source → per-item struct → SoA sink converts layout twice for nothing. |
| 20 | `unbox` | De-Rc (`Vec` instead of `Rc<RefCell<Vec>>`) | Cheap | **YOURS. The single biggest lever in the whole list** — 14 of their 32 loss diagnoses. Cheap to implement, largest multiplier. |
| 21 | `hoistborrows` | Borrow hoisting | Cheap | **YOURS** — if indirection must stay, borrow **once outside** the loop instead of per access. The cheap partial fix when 20 is not available. |

### Number representation (22–28)

| # | keyword | label | cost | verdict |
|---|---|---|---|---|
| 22 | `narrow` | i32 sequence narrowing (codegen) | Cheap | **design-time** — `Vec<i32>` over `Vec<i64>` halves cache footprint at zero instruction cost. Their graph_bfs: 120 MB → 60 MB. |
| 23 | `narrowvm` | i32 sequence narrowing (VM) | Cheap | n/a. |
| 24 | `narrowmap` | i32 map-key narrowing | Cheap | **design-time**. |
| 25 | `densemap` | Dense direct-addressed map | Cheap | **YOURS** — a hash/tree map over a small dense integer key is a `Vec` indexed directly. Check the key's actual range before proposing; a sparse key defeats it. |
| 26 | `elemtype` | Element-type narrowing | Medium | **design-time** — fixed-point `i32`/`u32` instead of `f64` is this optimization, banked. Never undo it for a rewrite's convenience. |
| 27 | `fastdiv` | Magic-reciprocal division | Cheap | compiler's **for compile-time constants**; **YOURS** only when the divisor is loop-invariant at runtime but unknown at compile time — a case both gcc and rustc leave as a real `div`. Do not confuse the two; see `llvm-already.md`. |
| 28 | `floatstrength` | Float induction strength reduction | Medium | compiler's under fast-math, **YOURS** otherwise — but changes rounding. Correctness before speed. |

### Bounds & checks (29–31)

| # | keyword | label | cost | verdict |
|---|---|---|---|---|
| 29 | `oracle` | Abstract interpretation | Medium | n/a (it is the machinery the next two need). |
| 30 | `oraclehints` | Bounds-check guards | Medium | **YOURS**, but prefer the safe form. A check on a *computed* index (`buf[i * stride + j]`) often survives; `chunks_mut(stride)` deletes both the arithmetic and the check with no `unsafe`. |
| 31 | `unchecked` | Proven unchecked indexing | Medium | **last resort** — this is the one entry in the registry flagged `emits_unsafe`. See the silent-failure warning below. |

### Strings & SIMD (32–35)

| # | keyword | label | cost | verdict |
|---|---|---|---|---|
| 32 | `simd` | SIMD search kernels | Cheap | **YOURS via a crate** (`memchr`, `aho-corasick`, `simd-json`) — but only above the amortization threshold. Below it, setup cost dominates. Measure the haystack. |
| 33 | `cascade` | Cascade folding | Cheap | compiler's. |
| 34 | `indexstring` | Indexed string search | Cheap | **YOURS** — repeated searches over a stable corpus want an index, not a faster scan. Algorithmic, so it outranks any SIMD win. |
| 35 | `capscale` | Capacity-scaling buffer fill | Cheap | **YOURS, and usually the cheapest item on any report.** If the final size is computable, `with_capacity` it. Look for the case where the code *already computed* the count for another purpose and then constructed the collection empty anyway. |

### Search-space (36–39)

| # | keyword | label | cost | verdict |
|---|---|---|---|---|
| 36 | `symmetry` | Symmetry breaking | Heavy | **YOURS**, domain-specific. |
| 37 | `popcount` | Popcount leaf collapse | Cheap | **YOURS** — bitset instead of a set-of-small-integers. |
| 38 | `saturate` | Equality saturation (e-graph) | Heavy | n/a. |
| 39 | `supercompile` | Supercompilation | Heavy | n/a. |

## The silent-failure warning on bounds hints

Both bugs LOGOS found in their own bounds-hint work were the same shape: `<=` where `<` was needed, on an inclusive loop bound. The consequence is the point:

- **A hint that is too weak is a silent no-op.** The optimization simply never fires, no test fails, nobody notices, and the "win" you reported never existed.
- **A hint that is too strong is UB.**

Neither failure mode is visible in a passing test suite. This is the argument for preferring the restructuring (`chunks_mut`, `zip`, `iter()`) over the assertion, and the assertion over `get_unchecked`, in that order — a form that cannot be got wrong in either direction beats a form that must be got right.

## Fast triage

Read in this order, stop when you have three findings:

1. **`unbox` / `hoistborrows`** (20, 21) — one grep. Present ⇒ largest multiplier available; absent ⇒ a real conclusion that redirects the whole survey.
2. **allocation in per-item paths** (17, 35, 13) — highest hit rate in practice.
3. **`interleave` / `fuse`** (19, 13) — representation churn at boundaries.
4. **`densemap` / `elemtype` / `narrow`** (25, 26, 22) — either already banked, or one type change.
5. Everything else, only if 1–4 came back clean.
