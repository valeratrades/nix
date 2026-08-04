# /optimize reference: the kill list — what the optimizer already does

Load this in Step 3. Every candidate from the census goes through it. An item that survives is a finding; an item that does not gets recorded under **Withdrawn** with the reason.

This step exists because the failure it prevents is invisible. A false finding does not crash — it gets implemented, measured at 0%, and blamed on measurement noise. Killing it costs thirty seconds; not killing it costs a day and leaves the code worse.

## The kill list

### Division / modulo by a compile-time constant

**Kill it.** The canonical fake finding. "I found a `/` in a hot loop" is not a finding. If the divisor is a literal, a `const`, an associated const, an enum discriminant, or anything a monomorphization pins, the backend emits a magic-multiply-and-shift. This has been true in LLVM and GCC for over a decade.

Watch for the divisor whose constness is one hop away:

```rust
let period = ts / Horizon::ns(tf);   // tf from <E as Cell>::CLOCK, an associated const
                                     // Horizon::ns is a `const fn`
                                     // ⇒ constant per monomorphization ⇒ already magic-multiplied
```

**The exception, and it is a real one.** A divisor that is *loop-invariant at runtime but unknown at compile time* is left as a genuine hardware `div` by both gcc and rustc. Hoisting a reciprocal out of the loop yourself (`libdivide`-style) is a strict win there. LOGOS implements `fastdiv` for exactly and only this case, and beats both compilers on it. So the question is never "is there a division" — it is **"is the divisor known at compile time?"** Different question, different answer, and only the second one is yours.

### `#[inline]` / `inline` / `__attribute__((always_inline))`

**Kill it, in a survey.** The optimizer is most reliably already doing this; it is `Cheap`/`TradesMemForSpeed` in the registry precisely because it is the low-effort thing everyone reaches for first. Hand-annotation mostly grows code and costs I-cache.

Two narrow places it is legitimate:

- a small hot leaf function across a **crate boundary** without LTO (`#[inline]` is what makes it available for cross-crate inlining at all)
- a case where you have the **disassembly** showing a real `call` that should not be there

It is a micro-win on a small algorithm and does not survive scale. It is never the answer to a systemic cost, and a survey whose top items are inline annotations has not found anything. **Do not put it on a recommendation list without disassembly.**

### CSE, LICM, unrolling, dead-code elimination, constant folding

**Kill all of them.** Rows 9–11, 14–16 of the registry, and all "compiler's". Rewriting source to hand-perform them changes the IR not at all.

The one carve-out on LICM: the compiler will not hoist something it cannot prove pure. A `read_dir`, an allocation, a lock acquisition, or any call through a `dyn` boundary blocks it. **That** is a finding — but write it up as "an impure call is loop-invariant", not as "LICM missed this".

### Bounds checks on idiomatic iteration

**Kill it.** `for x in slice`, `.iter()`, `.zip()`, `.chunks()`, `windows()` — all elided.

**Survives:** a *computed* index in an indexed loop, where the compiler must reassociate through a multiply to prove the range:

```rust
for i in 0..rows {
    out[i * stride + j] = ...;   // check may well survive
}
```

The fix is `out.chunks_mut(stride)`, which removes the arithmetic *and* the check with no `unsafe` and nothing to get wrong. Reach for `assert_unchecked` only when restructuring is genuinely impossible, and `get_unchecked` after that. See the silent-failure warning in `cannot-see-through.md`.

### `memcpy`-shaped loops, trivial `Default`, `Option` niches, small-struct returns

**Kill all.** Loops that copy are recognized and become `memcpy`. Niche optimization means `Option<&T>` and `Option<NonZeroU32>` are already free. Small structs return in registers.

### "Avoid the function call" / "flatten this abstraction"

**Kill it** unless there is a `dyn`, a function pointer, or a crate boundary without LTO. Zero-cost abstractions in Rust and C++ are, for once, actually zero-cost, and generic code monomorphizes. If a call survives, name *why* it survives — that reason is the finding, not the call.

## What survives, and why

The pattern behind the whole list: **the compiler optimizes computation, not representation, allocation, or I/O.** It will happily perfect the arithmetic of a loop that is spending 95% of its time chasing a pointer or in `malloc`.

Survives because the compiler is not *permitted*:

- **allocation strategy** — it cannot elide a `malloc`/`free` pair whose pointer escapes, and it must assume it escapes
- **data layout** — it cannot turn AoS into SoA; that changes the ABI
- **indirection** — it cannot prove an `Rc` count is one, or that a `RefCell` is uncontended
- **collection choice** — it cannot replace a `BTreeMap` with a `Vec`

Survives because the compiler does not *know*:

- **purity of external calls** — the fact your function is a pure function of small integers, so it can be memoized or tabulated
- **domain invariants** — this index is in range, this value is non-negative, this sequence is already sorted
- **workload shape** — this key is dense, this haystack is long, this branch is 99% taken

Survives because the compiler cannot *see it*:

- **syscalls in loops**, redundant I/O, format-level pushdown a decoder supports and you did not use
- **algorithmic complexity** — the compiler will not turn your O(n²) into O(n log n)

Ranked: the algorithmic and I/O items outrank everything else, then indirection, then allocation, then layout, then everything on the semantic-facts list.

## Verifying rather than guessing

When an item's fate genuinely turns on what the compiler did, look — it is faster than arguing:

```bash
cargo asm <crate>::<path>::<fn>              # cargo-show-asm
RUSTFLAGS="--emit=asm" cargo b --release     # crude but always available
perf stat -e instructions,cache-misses,branch-misses -- <cmd>
valgrind --tool=callgrind <cmd>              # deterministic instruction counts, no noise
objdump -d target/release/<bin> | less       # last resort
```

For a suspected constant-divisor kill, one grep for `mul`/`shr` versus `div`/`idiv` in the emitted function settles it in seconds. Write the check you ran into the withdrawn item so nobody redoes it.
