Done — and the tree is green: `cargo b` clean, `cargo t` 66/66. Your `160529d wip: composite Bars` swept my working tree in, so it's all on `main` already.

## What landed

**Classify** now takes 12 deps: `Gating<Screener>`, `Bar1m`, `Buffering<Bar5m>`, `Buffering<Bar4h>`, `Change1d`, `Change3m`, `Volume1m`, `Volume1h`, `Imbalance`, `Spread`, `Buffering<McRoot, Elems(1)>`, `Buffering<OiRoot, OI_REACH>`. `Situation` grew to 9 fields, 3 new traits (extended-day → Liquidations, wide+skewed book → Manipulation, minute-vs-hour volume surge → Momentum), and `change_15m` → `change_3m`. Outputs are `{ deprecator, rsi }`.

## Four things your prompt didn't account for

1. **"Remove Bars deps" is only partly honoured — only `Bar15m` went.** `Bar1m`, `Buffering<Bar5m>` and `Buffering<Bar4h>` had to stay: `momentum::standing(m5, h4)` is computed inline (`Momentum` itself is only reachable to a gated node through `Folding`, which a gated node is forbidden to hold), and `oi_value` needs a price because `Oi.oi` is base-coin while the market cap is USD — `m1.last().close` is the only close available.

2. **The six new deps forced a gate cascade.** `shadowed` rejects a bounded, ungated node whose every non-latched consumer sits behind one gate. Change1d/Change3m/Volume1m/Volume1h/Imbalance/Spread are now consumed only by `Classify`, so all six had to take `Gating<Screener>` themselves. That then shadowed `BookTop` — its only non-latched consumers became Imbalance and Spread (the `Deprecator` is excluded because its gate is a latch). Gating `BookTop` would have starved the trailing stop, so instead its dep is now `Folding<trading_data::Book, Unbounded>`, which is true anyway: the book is the accumulation of every delta since its anchor.

3. **Imbalance and Spread will read `None` on nearly every hit.** They're book-clocked; the gate is 1m/trades-clocked. As plain deps they can't be buffered either — `impl Node for Buffer<C,H>` requires `C::Item: Stamped`, and `Option<f64>` isn't. Their trait effectively never votes. `//TODO` marks it in `Situation`.

4. **spl's candle chart is gone.** `viz.bar(BarOut)` was the only source of candles and it needed `out.bar_1m`; with outputs pinned to two, I deleted the feed and passed `price_node: None` so `Bar:1m` at least draws as an ordinary indicator pane.

Also: four thresholds I invented and that move the live vote — `EXTENDED_1D=20.0`, `WIDE_SPREAD=0.1`, `SKEWED_BOOK=0.5`, `VOLUME_SURGE=3.0` — plus `CASCADE_DROP=-7.0` is now read over 3m instead of 15m. All carry `//TODO: untuned.`