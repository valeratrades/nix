<prompt>
I'm pretty sure /home/v/math/s3/functions_in_real_values/td1.typ:120 goes to zero, - the part with ^(1/4) I can just take out as a separate multiplier and show it's going to 0, but what about the part with logs. Hint to what I should do there. I think we've already done something similar last year, but I forgot the transposition rules, - if we already have my own solutions of similar problems,  - just link them and also outline the methods that are available to me to use here
</prompt>

**Hint:** pull `√n` and `ln n` out, so that only `(1+1/n)` stays inside the root and the log. Then expand in `u = 1/n → 0`:

```
√(n+1)  = √n · (1+1/n)^(1/2)  = √n · (1 + 1/(2n) + O(1/n²))
ln(n+1) = ln n + ln(1+1/n)    = ln n + 1/n + O(1/n²)
```

Multiply out the numerator. The two `√n·ln n` terms cancel, and the first term left over is `√n·ln n/(2n) = ln n/(2√n)` (the `−1/√n` term is smaller). Divide by `n^(3/4)`, and you get `u_n ~ ln n / (2·n^(5/4))`.

Two warnings about what you have at line 120:
- The ratio test can't settle this one. `u_(n+1)/u_n → 1` for anything polynomial-times-log, so it gives no answer.
- `u_n → 0` is true, but it's only necessary. It doesn't show that `∑ u_n` converges. You need an equivalent of `u_n`, then a comparison.

```
u_n ──factor √n, ln n──▶ √n·[(1+u)^½·ln n − ln n − ln(1+u)] / n^¾
     ──DL at u=1/n────▶ leading ln n cancels ⇒ must expand, can't use ~ on a difference
     ──~ for u_n>0 ───▶ u_n ~ ln n / (2 n^(5/4))
     ──ln n = o(n^ε)──▶ ≤ C/n^(9/8)  ⇒ Riemann α=9/8>1 ⇒ ∑ converges
```

**Methods you've already used:**

| Tool | Where you did it |
|---|---|
| `(1+u)^α = 1 + αu + α(α−1)/2·u² + o(u²)` | `l1/s2/series/__main__.typ:55-68` (`√(1+2x)`) |
| `ln(1+u) = u − u²/2 + o(u²)` | `l1/s2/series/__main__.typ:113-114` |
| Factor out the dominant term, then DL the `(1 + small)^α` | `l1/s2/series/__main__.typ:975-981` (`n((1+1/n³)^(1/3) − 1) ~ 1/(3n²)`), which is the closest match to this problem |
| Plug `u = 1/n` into a DL, then compare with `1/n^α` | `l1/exams/.../EI-type.typ:121-139`, `l1/s2/finals_prep/previous_years_section.typ:287-288` |
| Growth order: `ln n ≪ n^ε` | `l1/s2/series/__main__.typ:899` |

Rules for moving `~` around:
- `~` passes through products, quotients and powers.
- It does not pass through sums or differences. When the leading terms cancel, as they do here, you have to use a DL with `o(·)`.
- If `u_n, v_n > 0` eventually and `u_n ~ v_n`, then `∑u_n` and `∑v_n` have the same nature. Here `u_1 < 0`, but the sign is constant for large `n`, and that's all you need.

I haven't checked that the exercise asks for the nature of `∑ u_n`. I assumed that from the ratio test you started.