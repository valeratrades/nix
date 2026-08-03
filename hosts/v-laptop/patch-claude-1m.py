#!/usr/bin/env python3
"""Stop claude-code's `/model` picker from refusing `opus[1m]` on a Max subscription.

Context: extended context is documented as included with Max — "On Max, Team, and
Enterprise plans ... Opus is automatically upgraded to 1M context with no additional
configuration", and only Sonnet 4.6 with 1M requires usage credits. The `--model` flag
honours that: `claude -m 'claude-opus-5[1m]'` runs fine on this account. The interactive
`/model` switch does not — it runs an extra validator that answers "Opus with 1M context
is not available for your account".

That validator gates on `!aY()&&!KO()`. `aY()` resolves, for a claude.ai login, to the
extra-usage state, which here is `org_level_disabled` — a Sonnet-1M/Pro condition that
has no bearing on Opus on Max. `KO()` is the sub-expression that should carry Max through
(firstParty, not Pro, `subscriptionType === "max"`) and reads as true for this account,
so the gate should never fire in the first place. It fires anyway. Since the flag path
proves the server grants the model, the refusal is client-side only.

Fix: neutralize the predicate so `/model opus[1m]` and `/model claude-opus-5[1m]` are
accepted, matching what `-m` already does.

Deliberately NOT patching the sibling Sonnet gate (`Q2s`): Sonnet 4.6 with 1M genuinely
requires usage credits on every plan including Max, so unblocking it client-side would
only buy a server-side rejection later. If Anthropic ever gates Opus-1M on Max for real,
this patch will likewise stop helping — the failure would then move server-side, which is
the honest place for it.

Same-length overwrite (replacement padded with spaces) so Bun's compiled-ELF trailer
offsets stay valid — same technique as strip-claude-reminders.py / patch-claude-altexit.py.

The anchor's occurrence count is asserted so the build fails LOUDLY if upstream changes
the minified wording.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-1m.py (in your nix config)"

# Body of the opus-1m availability predicate, verbatim from claude-code 2.1.220.
# Full function: function J2s(e){let t=e.toLowerCase();<ANCHOR>}
# Must occur exactly once.
ANCHOR = b'return!aY()&&!KO()&&t.includes("opus")&&t.includes("[1m]")'
REPLACEMENT = b'return!1;'.ljust(len(ANCHOR))
assert len(REPLACEMENT) == len(ANCHOR), "same-length overwrite required"


def die(msg: str) -> None:
    sys.stderr.write(
        "\n"
        "================================================================================\n"
        "  claude-code opus-1m /model gate patch FAILED\n"
        "================================================================================\n"
        f"  {msg}\n"
        "\n"
        "  This patch stops the interactive /model picker from rejecting opus[1m] with\n"
        '  "Opus with 1M context is not available for your account" on a Max plan, where\n'
        "  extended context is included. The --model flag already accepts it.\n"
        "  Upstream has likely changed the minified predicate or its variable names.\n"
        "\n"
        "  To fix:\n"
        f"    1. Edit {THIS_FILE}\n"
        "    2. Find the predicate in bin/.claude-unwrapped:\n"
        "         grep -ao 'function [A-Za-z0-9_$]*(e){let t=e.toLowerCase();return![^}]*1m[^}]*}' <binary>\n"
        "       It is the one reached from the 'Opus with 1M context is not available'\n"
        "       message; the neighbouring Sonnet predicate is intentionally left alone.\n"
        "    3. Update ANCHOR to match (keep the overwrite same-length), or drop this\n"
        "       override (see patched-claude-code.nix).\n"
        "\n"
        "  Before re-patching, check whether it is still needed: if /model opus[1m] is\n"
        "  accepted unpatched, upstream fixed it and this file should just be deleted.\n"
        "================================================================================\n"
    )
    sys.exit(1)


path = sys.argv[1]
with open(path, "rb") as f:
    data = f.read()

original_len = len(data)
count = data.count(ANCHOR)
if count != 1:
    die(f"expected 1 occurrence of the opus-1m predicate in {path}, found {count}.")

data = data.replace(ANCHOR, REPLACEMENT)
assert len(data) == original_len, "overwrite must preserve byte length"

with open(path, "wb") as f:
    f.write(data)

print("patched opus-1m gate -> /model accepts opus[1m]", file=sys.stderr)
