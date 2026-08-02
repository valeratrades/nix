Builds clean.

- `invalidates_others: true` subtracts that trait's relevance from every other category; sums floor at 0 before normalising.
- Set on the large-cap → Momentum trait only.

skipped: a test — `vote` is private with no existing test module here; the `total > 0.0` assert still guards the degenerate case (an invalidator always leaves its own category ≥ its relevance while it's the only one).