# /optimize reference: the harness

Load this in Step 5. No item is implemented before its four properties hold. The discipline here is lifted from benchmark-suite practice, where the incentive to fool yourself is maximal and the countermeasures are therefore mature.

## The four properties

### 1. A cached baseline

Measure the current state once, commit the numbers, re-measure only the side that changed. A suite that re-measures both sides every run drowns real deltas in machine noise and drift.

```bash
cargo bench -- --save-baseline before     # criterion
cargo bench --bench <name>                # iai-callgrind: writes .last, diffs automatically
```

Commit the baseline file. It is the only thing that makes a delta three weeks later meaningful, and it is what lets a reviewer check your number without a machine identical to yours.

### 2. A verify gate

**The benchmark must refuse to time an implementation whose output does not match the reference.** Not a test that runs beside it — a gate inside it.

The failure this prevents is the one you will actually hit: an optimization that is subtly wrong is usually also fast, because skipping work is what made it wrong. Every large "win" is a wrong-answer suspect until the gate has passed.

```rust
let got = optimized(&input);
assert_eq!(got, reference(&input), "optimized output diverged");
b.iter(|| optimized(black_box(&input)));
```

If a replay-equality, golden-file, or snapshot test already exists, wire *it* into the bench rather than writing a second reference.

### 3. A control that must not move

Keep at least one benchmark exercising a path the change should **not** touch. If it moves, the change reached further than intended — a shared function, an allocator behaviour, an inlining cascade — and needs re-reading before the primary number is believed.

Canonical controls are latency-bound and immune to codegen luck: an LCG chain, a pointer chase. A domain control is better still — the same engine with the feature you are optimizing disabled. If you are optimizing ingest, the core loop with no ingest attached must not move at all.

**The control catches more real mistakes than the primary measurement does**, because the primary measurement is the one you are motivated to believe.

### 4. Suspicion of large wins

Anything better than **~10×** is assumed to have stopped doing the work until proven otherwise.

The reference incident: a recursive-Fibonacci benchmark went 415 ms → 2.7 ms when memoization landed. That is a real optimization and a real 150× — and the suite correctly recorded it as a **measurement-integrity finding**, not a result. Memoization had changed the benchmark's complexity class, so the benchmark had stopped measuring the thing it existed to measure.

Two things to do when a number is too good:

- **Scale it.** Run at 2× and 4× input. A genuine constant-factor win holds its ratio across sizes. A complexity change does not — and a *dead-code elimination* shows a ratio that grows without bound.
- **Check the output is still consumed.** `black_box` on both the input and the result. A benchmark whose result is unused measures nothing, arbitrarily fast.

## Tool choice

| Tool | Use for | Note |
|---|---|---|
| `iai-callgrind` / `valgrind --tool=callgrind` | small deltas, CI | deterministic instruction counts, no noise, works on a loaded machine — the right default for a 3–15% change |
| `criterion` | wall-clock with statistics | needs a quiet machine; will not resolve <5% reliably |
| `perf stat` | which resource is the bottleneck | `-e instructions,cycles,cache-misses,branch-misses`; IPC tells you cache-bound vs branch-bound vs actually-computing |
| `perf record` / `flamegraph` | finding the hot path when it is unknown | Step 1's volume model is usually faster and more honest than a profile for *ranking*, but a profile is authoritative for *locating* |
| `strace -c` | class 5 (syscalls in loops) | a count is often the whole finding |
| `heaptrack` / `dhat` | class 1 (allocation) | allocation **count** is the number that matters, not bytes |

Instruction counts do not capture cache effects, so a layout change (`interleave`, `narrow`) needs wall-clock on realistic data; an allocation-removal shows up cleanly in instruction counts. Match the tool to the class.

## Wall-clock on real input, always, for I/O

Anything touching the filesystem, the network, or compression needs a wall-clock run on a real input file in addition to any micro-benchmark. Microbenchmarks of I/O paths measure the page cache.

## Recording

Every implemented item gets its measured delta written into the report next to it, with the tool and the input size. Two rules:

- **A miss is data.** An item that lands under its estimate corrects the volume model — go fix the model, because everything ranked below it was ranked using it.
- **Stop and re-survey after two consecutive items under 5%.** The ranking is wrong, and continuing down a wrong ranking is worse than redoing Step 1.

## The ≥2-site rule

Before a *pattern* is ranked near the top, confirm it fires at two or more structurally distinct sites. One site is a special case: fix it, rank it as one item. This is the anti-gaming rule from benchmark-suite practice — there, a pattern that fires on exactly one benchmark is overfitting to the suite rather than optimizing the language. Here, it is what stops a survey from over-ranking whichever function you happened to read first.

The converse is a ranking rule too: items that **compose** — three allocations removed by one rewrite of the same loop — multiply rather than add, and ranking them separately understates all three. Group them into one entry.
