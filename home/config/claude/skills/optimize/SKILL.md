---
name: optimize
description: "Use when asked to make a codebase faster, to find performance wins, to evaluate whether a specialized crate/library (memchr, aho-corasick, rayon, simd-json, mimalloc…) is worth adopting, or to review a hot path for close-to-the-wire performance. Produces a ranked, site-cited optimization report grounded in what the compiler cannot already do for you — and refuses to invent findings the optimizer already handles."
---

# /optimize

Survey a codebase for close-to-the-wire performance wins, rank them by expected payoff, and write a report where every entry names a **file:line**, the **mechanism** of the cost, and the **fix**. Optionally implement them in order behind a measurement harness that can prove the change did something.

## Usage

```
/optimize                                  # survey the current repo, write the report
/optimize <path>                           # survey a specific crate/dir/subtree
/optimize <path> --crate <name> [<name>…]  # also answer "is <crate> worth adopting here?" honestly, including "no"
/optimize <path> --hot <entrypoint>        # you already know the hot path; skip discovery, go deep
/optimize --pass2                          # re-read an existing report through the taxonomy; kill dead items, sharpen the rest
/optimize --measure                        # build the harness only (baseline, controls, verify gate) — no changes
/optimize --implement                      # work the existing report top-down, one item per commit, measured
/optimize --implement <n>                  # implement item <n> only
```

## What /optimize is for

Most "make it faster" work fails in one of two ways: it finds things the optimizer already does (wasted effort, sometimes a regression), or it finds real things in the wrong order (a 3% win landed before a 40x one). This skill exists to prevent both. Its central claim, which is empirically grounded and is the thing to internalize:

> **Never compete with the compiler. Spend everything on what the compiler cannot see through.**
>
> LLVM/GCC reliably do inlining, CSE, LICM, unrolling, constant-divisor strength reduction, and bounds elision on iterator patterns. They cannot see through an indirection wrapper, an allocation strategy, a data layout, or a semantic fact that died in translation. The wins are all on the second list.

The sharpest available evidence for this is a natural experiment in the LOGOS compiler's benchmark suite: across 32 programs measured against C, the ones where a plain **slice** reached the hot loop landed at 0.98–1.11× of C, and the ones where a per-access `RefCell` **borrow** reached it landed at 1.5–4.6×. Same optimizer, same LLVM backend, same source language. The *type at the hot loop* was the entire difference. See `references/cannot-see-through.md`.

## What You Must Do When Invoked

If invoked with `--help` or `-h` and nothing else, print the `## Usage` block verbatim and stop.

If no path was given, use the repo root. Do not ask the user for a path.

If the user named specific crates/libraries (`--crate`, or just asked "would memchr help here?"), **Step 0 is mandatory and its answer goes at the top of the report** — including when the answer is no. Do not bury a "no" in the body, and do not manufacture a use to be agreeable.

Work the steps in order. Steps 1–4 are read-only; nothing is modified before Step 5.

---

### Step 0 — Answer the framing question first, including "no"

Only if the user named a technique or dependency. For each one, find its **consumer** in this repo before evaluating it. A library is worth adopting only if there is an existing site whose shape it matches, at a volume where it amortizes.

Three failure modes to check explicitly, because each has burned a real survey:

- **No consumer exists.** (`aho-corasick` needs *multi-pattern* search. If the repo never searches for more than one pattern at a time, there is nothing to accelerate, and automaton construction makes it strictly slower.)
- **The consumer is below the amortization threshold.** SIMD string search pays off on long haystacks; on five CSV fields of under twelve bytes each, setup cost dominates. Say so with the measured field size, not as a guess.
- **The consumer does not run at runtime at all.** If the candidate call sites are `const fn` / `constexpr` / comptime, adopting a runtime library **forces them out of compile time** — a regression dressed as an optimization. Grep for `const fn`/`constexpr` on the enclosing function before proposing anything.

Also check what the standard library already does. `BufRead::read_until` and `lines()` already use `memchr` internally; adding the crate to "speed up newline scanning" buys exactly nothing.

Write the verdict as a short paragraph per named crate. If the answer is no, say **"Recommend not adding it"** and then point at what the real cost turned out to be.

### Step 1 — Build the volume model before reading any code closely

You cannot rank without a denominator. Before profiling and before reading implementations, establish how often each layer runs. Read entry points and loop nests only, and write down a table:

| Layer | Runs per | Typical count |
|---|---|---|
| e.g. per-field parse | message | 800 |
| per-message decode | file | ~10^6 |
| per-file flush | run | ~10^3 |

This table is what makes ranking honest and non-negotiable later. A `String` allocation costs the same everywhere; it matters at 10^8/day and does not matter at 10^3/day. **An item's rank is `per-call cost × call-site volume`, and the volume number must appear in the report entry.** Without this step you will rank by how egregious the code looks, which is how 3% wins get landed first.

Cheap ways to get the numbers: read the loop structure; count fields in a representative input record; `wc -l` a real input file; check batch/chunk sizes in config.

### Step 2 — Run the census

Five greps, each targeting a class the compiler cannot fix. Run all five even if one seems obviously empty — **the negative results are load-bearing**, they tell you where not to spend effort, and a clean census on one class is a genuine finding to report.

The commands, per language, are in `references/census.md`. The classes:

1. **Allocation in a per-item path** — the single highest-yield class in practice. A `String`/`Vec`/`Box` constructed and dropped inside the innermost loop.
2. **Indirection at the hot loop** — `Rc`/`RefCell`/`Arc<Mutex>`/`Box<dyn>`/virtual dispatch reaching per-item code. This is the class with the largest single multiplier when present.
3. **Representation churn** — a collection rebuilt from data that already has the property the collection provides (a `BTreeMap` built from an already-sorted sequence); a layout round-trip (SoA → AoS → SoA); a value round-tripped through a wider or lossier type.
4. **Fixed-size work on the heap** — a `Vec` whose length is a compile-time constant, or a buffer reallocated per iteration that could be caller-owned scratch.
5. **Syscalls and I/O inside a loop that could hoist or push down** — a directory re-listed per write; a decode-everything-then-filter where the format supports predicate pushdown; compression on the latency-critical thread.

Record each hit as `file:line` immediately. Do not evaluate yet.

### Step 3 — Apply the kill filter

This is the step that separates this skill from a generic code review, and it is the step to spend real thought on. For every candidate from Step 2, ask: **would the optimizer already do this?** If yes, delete the item.

The kill list is in `references/llvm-already.md`. The ones that most often produce false findings:

- **A division by a compile-time constant.** "I found a divide in a hot loop" is the classic fake finding. If the divisor is a `const`, an associated const, or anything a monomorphization pins, the compiler emits a magic-multiply and there is nothing to do. Strength reduction is only *yours* to do when the divisor is loop-invariant at runtime but unknown at compile time — a genuinely different and much rarer case.
- **`#[inline]` / `inline` annotations.** Cheap-looking, and the thing the compiler is most reliably already doing on its own. Hand-annotating mostly grows code size and costs I-cache. It can win on a small hot leaf function across a crate boundary; it does not survive scale, and it is never the answer to a systemic problem. **Do not put `#[inline]` on a survey's recommendation list** unless you have the disassembly showing a real call that should not be there.
- **A fold or comparison over compile-time-known data.** Constant-folds.
- **Bounds checks on an idiomatic iterator.** Already elided. Bounds checks on a *computed* index (`buf[i * stride + j]`) genuinely may not be — but the fix is to restructure into `chunks_mut(stride)` so the check disappears with no `unsafe`, not to reach for `get_unchecked`. See the warning in `references/llvm-already.md` about hint bugs failing silently.

When you kill an item, **keep it in the report under a "withdrawn" heading with the reason**. The killed items are the most instructive part of the document for the next reader, and they stop the same finding being re-proposed next quarter.

### Step 4 — Write the report

Default destination: `tmp/ongoing_dev/performance_optimizations.md` (create the directory). If the repo has an established location for working notes, use it.

Structure, in this order:

1. **Verdicts on any named crates** (Step 0), up front, "no" included.
2. **The volume table** (Step 1).
3. **Ranked items.** One `##` section each, ordered by `cost × volume`. Every entry must have:
   - the site as `path/file.rs:LINE` — a claim without a line number is not a finding
   - the **mechanism**: what specifically costs, in one or two sentences
   - the **volume**: how often it runs, from the Step 1 table
   - the **fix**: concrete enough to implement from, including which interface has to change
   - if it is not certain, the sentence that would settle it (*"confirm in the disassembly before touching — if a magic-multiply is already emitted, this item is void"*). Then go settle it.
4. **Withdrawn items** with reasons (Step 3).
5. **Negative results** — the classes that came back clean. "No `Rc`/`RefCell`/`Box<dyn>` reaches any per-item path" is a *conclusion*: it says the representation work is already done and effort belongs elsewhere.
6. **Correctness findings.** Performance surveys turn these up constantly, because the same instincts that spot a wasteful conversion spot a lossy one. Promote them above every performance item; a nanosecond timestamp round-tripped through `f64` is a bug that a rewrite fixes for free. Flag them as **correctness, not speed**.
7. **Measurement plan** (Step 5) and **implementation order**.

Two discipline rules for the ranking:

- **The ≥2-site rule.** A proposed *pattern* should fire at two or more structurally distinct sites before it earns a top rank. One site is a special case; fix it, but rank it as one. This is directly borrowed from benchmark-suite anti-gaming practice and it is what stops a survey from optimizing the one function you happened to read first.
- **Items that compose rank as a group.** Three allocations in the same per-line loop are removed by one rewrite and multiply together; ranking them separately understates all three.

### Step 5 — Build the harness before changing anything

If `--implement` was requested, this step is not optional and comes first. Four properties, from benchmark-suite practice (`references/measurement.md`):

1. **A cached baseline** — measure the current state once, commit the numbers, and re-measure only the side that changed.
2. **A verify gate** — the benchmark refuses to time an implementation whose output does not match the reference. Wire the existing equality/snapshot test *into* the bench, not beside it.
3. **A control that must not move** — a benchmark exercising a path the change should not touch. If it moves, the change reached further than intended and needs re-reading. This catches more real mistakes than the primary measurement does.
4. **Suspicion of large wins.** Anything reporting better than ~10× is assumed to have stopped doing the work until proven otherwise. A memoization that turned an exponential benchmark linear reported a 150× "win" and was correctly recorded as a *measurement-integrity failure*, not a result.

If an item has no benchmark at all, it gets one before it gets a patch. Instruction-count tools (`iai-callgrind`, `perf stat`) are preferable to wall-clock for small deltas; wall-clock on real input is still required for anything touching I/O.

### Step 6 — Implement top-down, one item per commit

In report order. After each: run the bench, run the control, run the test suite, record the delta in the report next to the item. If an item comes in under its estimate, say so in the report — a miss is data about the volume model and should correct it.

Stop and re-survey if two consecutive items land under 5%. That means the volume model was wrong, and continuing down a bad ranking is worse than redoing Step 1.

---

## Where the taxonomy comes from

`references/cannot-see-through.md` distills the 40 optimizations the LOGOS compiler implements, grouped by what class of thing they exploit, with a verdict on which are *yours* to do by hand in an already-compiled language. It is the checklist to read code against in Step 2, and it is deliberately organized so that the classes with no applicability to your repo are fast to rule out.

The source of truth is `crates/logicaffeine_language/src/optimization.rs` in the LOGOS repo (a `REGISTRY` of 40 `OptMeta` entries with `group`, `cost`, `mem_class`, `requires`/`conflicts`). Note that the rendered benchmarks page does **not** contain the list — it is generated client-side from that registry. When gathering references, go to the source that generates the artifact, not the artifact.

## Evaluation criteria

A finished `/optimize` run is judged on these, in order:

1. **Every item cites a line.** No `file:line`, no finding.
2. **Every item states its volume.** An unranked list is a list of opinions.
3. **The report contains at least one "no".** A survey that recommends adopting everything asked about, or that finds no killed candidates, did not apply Step 3. A `--crate` question answered "yes" three times out of three is a red flag on the survey, not a green light on the crates.
4. **Negative results are reported as results.** A clean census class is a conclusion about where effort belongs.
5. **Correctness findings are promoted above performance findings.**
6. **No `#[inline]` recommendations** without disassembly.
7. **No `unsafe` proposed** where a safe restructuring (`chunks_mut`, iterators, a caller-owned scratch buffer) achieves the same elision.
8. **Nothing is implemented without a control benchmark that did not move.**

## Honesty rules

- Never propose an optimization you have not located in the code. A pattern you expect to be there is not a finding.
- Never propose something the compiler already does. If unsure whether it does, say so in the item and go check the disassembly before ranking it.
- Never quietly drop a killed item — record the kill and the reason.
- Never report a speedup without its control.
- Never widen a type for convenience during an optimization pass. If the codebase chose `i32`/`u32` fixed-point over `f64`, that *is* an optimization already banked (cache footprint at zero instruction cost); undoing it to simplify a rewrite is a regression that will not show up in the benchmark you are watching.
- A benchmark improvement that the volume model does not explain is not understood yet. Explain it or withdraw it.
