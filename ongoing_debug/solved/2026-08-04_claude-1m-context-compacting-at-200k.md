# Claude Code auto-compacted at 200k despite `claude-opus-5[1m]` + `autoCompactWindow = 500000`

Solved 2026-08-04. CC 2.1.220. Fix: commit `e1cacd40`.

## Symptom
Model set to `claude-opus-5[1m]` (1M-context variant) and
`autoCompactWindow = 500000` in `~/.claude/settings.json`, yet every session
auto-compacted at ~200k. `/context` reported `x / 200k`.

## Root cause
`os/nixos/desktop/environment.nix` set `CLAUDE_CODE_DISABLE_1M_CONTEXT = "1"`,
inherited by every shell via `/etc/set-environment`.

Decompiled from the bundled JS (`bin/.claude-unwrapped`, bun single-file exe;
`rg -a --text -o` on the ELF reads the embedded source fine). Chain, with the
minified names as of 2.1.220:

```js
function O6e(){ return Z.CLAUDE_CODE_DISABLE_1M_CONTEXT }
function Wb(e){ if(O6e()) return !1; return /\[1m\]/i.test(e) }   // "[1m] suffix requests 1M"
function IP(e){ if(O6e()) return !1; /* native_1m capability + provider check */ }

function mZc(e,t){                       // resolve raw context window
  if(Wb(e)) return 1e6;                  // <- short-circuited to false by the env var
  if(t?.includes(v_e.header)&&Q8(e)) return 1e6;
  if(IP(e)) return 1e6;                  // <- same
  ...
  return ber                             // ber = 200000
}
function Xv(e,t){ ... if(m7i(e,t)) return gxe /*200000*/; return mZc(e,t) }

function o7(e,t){                        // (model, settings.autoCompactWindow) -> window
  let o = Xv(e,n);
  if(process.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW){ ...return {window: Math.min(o,c), source:"env"} }
  if(t!==void 0) return {window: Math.min(o,t), configured:t, source:"settings"};
  ...
}
```

So the env var kills the `[1m]` suffix **before** it is ever read, the window
resolves to 200k, and `o7` then `min()`s the configured 500k down to 200k. The
setting was never wrong — it had nothing to clamp against. Settings-schema
bounds are `min 1e5 / max 1e6`, so 500k is legal.

Origin of the env var: it was added in the same block as `DISABLE_TELEMETRY` /
`CLAUDE_CODE_DISABLE_AUTO_MEMORY` / `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`
(gh issue 42796), presumably to avoid 1M premium pricing. That trade is no
longer wanted.

## Fix
Delete `CLAUDE_CODE_DISABLE_1M_CONTEXT` from
`os/nixos/desktop/environment.nix`, `nixos-rebuild switch`, start a new shell.
`environment.variables` lands in `/etc/set-environment`, so already-running
shells (and any `claude` launched from them) keep the stale value — the session
that was open during the rebuild stays at 200k until restarted.

## Verified
```
$ env -u CLAUDE_CODE_DISABLE_1M_CONTEXT claude -p "/context"
**Model:** claude-opus-5[1m]
**Tokens:** 24k / 500k (5%)
| Free space         | 443k | 88.6% |
| Autocompact buffer |  33k |  6.6% |
```
and `grep -c CLAUDE_CODE_DISABLE_1M_CONTEXT /etc/set-environment` → 0.

Entitlement checked independently — a direct
`POST /v1/messages` with `anthropic-beta: context-1m-2025-08-07` on both
`claude-opus-5` and `claude-opus-4-5` returned 200 under this `ANTHROPIC_API_KEY`.
(An API key is metered pay-as-you-go, so the Max-sub Extra-Usage gate that the
old `claude.nix` comment described does not apply on this auth path.)

## The one remaining clamp (watch for this)
There is a second, *runtime* path back to 200k that no setting overrides:

```js
function H9t(){ return Ot.longContext1mCreditsBlocked }
function m7i(e,t){ return H9t() && fZc()===void 0 && mZc(e,t)>gxe }   // -> Xv returns 200000
```

`longContext1mCreditsBlocked` is latched by `CSi(!0)` from exactly one place:
the 429 handler, when the response body matches "credits are required /
extra usage is required" (telemetry event `tengu_1m_credits_clamp_activated`,
`context_1m_entitlement: credits_clamp_200k`). It is session-local process
state, not persisted — **restart `claude` to clear it**. If compaction ever
starts firing at 200k again with the env var gone, this is the cause, and it
means the account genuinely lost the 1M entitlement.

Patching `H9t()` to `return !1` would suppress the clamp, but it is a graceful
degrade, not the disease: without it the same requests just 429. Not done.

## Escape hatches found while reading, for reference
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW=<n>` — env override, outranks the setting,
  still `min()`'d against the real window. `source:"env"` in `/context`.
- `DISABLE_COMPACT=1` + `CLAUDE_CODE_MAX_CONTEXT_TOKENS=<n>` — `fZc()` returns
  the value and bypasses `Xv`'s model lookup entirely. Disables compaction
  rather than moving it, so you hit the hard context error instead. Not used.
- `/autocompact` slash command writes the same `autoCompactWindow` setting.
