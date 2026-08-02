**Fixed and verified on a full replay:**

```
before:  std_hits=310 classifications=310 episodes=0  intents=0
after:   std_hits=310 classifications=310 episodes=11 intents=216247
```

Clean — no `flag!` invariant violations. Deprecator's first Intent lands at `1779346800000`, the exact minute `Classify` first fires, and `Armed<Deprecator>` now commutates instead of latching open to the end of the day.

The change is three lines in `deprecator.rs`, at the one consumer that wants the value:

```rust
// The arming tick and the ticks that act on it are different lanes: `Classify` is trade-clocked,
// and every book tick that could enter on it is a later one. The latch carries the *fact* of the
// hit across them, this carries its content — and the commutation reset drops both together, so
// no episode enters on the classification of the one before it.
if classify.is_some() {
    self.last_classify = classify;
}
```

The commutation reset is what keeps it honest: `Emitter::reset` sets the node to `Default`, so `last_classify` clears with the episode and the next one can only enter on a classification that fired after the latch re-armed. I left your `//TODO: unreachable — see Lanes` in place with a `//REVIEW` under it.

Two notes:

- Your tree moved under me mid-run (`examples/demo` → `examples/simple`, tracey, the facade rule). `Plot::solo` and the deprecator fix are both in your `a577db6`; `cargo b -p trading_data_spl` is green against the current tree. Nothing of mine is left uncommitted in `trading_data`.
- Your instance on 59993 is running a deleted binary image (`/proc/1535905/exe -> ... (deleted)`) — it 404s on `/api/seek_ts` and predates the Deprecator fix. It needs a restart to get either, but that costs you the tape, so I left it alone.