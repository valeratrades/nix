#!/usr/bin/env python3
"""Force claude-code to ALWAYS interrupt the current turn when you submit while it's
busy, instead of silently folding your new prompt into the in-progress exchange.

Context: when you submit a prompt mid-turn, claude-code only aborts the running turn if
`hasInterruptibleToolInProgress` is true (i.e. a tool is actively executing). While the
model is merely thinking / streaming text ("yet to answer"), that flag is false, so the
submit branch skips the abort and just enqueues — the prompt waits and rides along with
the ongoing exchange rather than interrupting it. We want every mid-turn submit to be a
hard interrupt that starts a fresh turn; rolling back to edit the previous message is an
explicit Esc, not an implicit side effect of typing fast.

Fix: neutralize the `hasInterruptibleToolInProgress` gate so the abort always fires. The
condition `H.hasInterruptibleToolInProgress` is overwritten with `true` (same-length,
space-padded) — the abort + enqueue that follow then run unconditionally, which is the
exact path that already worked correctly for the tool-in-progress case.

Same-length overwrite (replacement padded with spaces) so Bun's compiled-ELF trailer
offsets stay valid — same technique as strip-claude-reminders.py / patch-claude-altexit.py.

The anchor's occurrence count is asserted so the build fails LOUDLY if upstream changes
the minified wording.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-queuejoin.py (in your nix config)"

# The mid-turn submit guard, verbatim from claude-code 2.1.154. Must occur exactly once.
ANCHOR = b'if(H.hasInterruptibleToolInProgress){'
COND = b'H.hasInterruptibleToolInProgress'
REPLACEMENT = ANCHOR.replace(COND, b'true' + b' ' * (len(COND) - len(b'true')))
assert len(REPLACEMENT) == len(ANCHOR), "same-length overwrite required"


def die(msg: str) -> None:
    sys.stderr.write(
        "\n"
        "================================================================================\n"
        "  claude-code always-interrupt-on-submit patch FAILED\n"
        "================================================================================\n"
        f"  {msg}\n"
        "\n"
        "  This patch forces a mid-turn prompt submit to always abort the running turn\n"
        "  (instead of folding into it when no tool is executing). Upstream has likely\n"
        "  changed the minified submit guard or its variable names.\n"
        "\n"
        "  To fix:\n"
        f"    1. Edit {THIS_FILE}\n"
        "    2. Find the mid-turn submit branch in bin/.claude-unwrapped:\n"
        "         grep -ao 'hasInterruptibleToolInProgress[^}]*abort(\"interrupt\")' <binary>\n"
        "    3. Update ANCHOR/COND to match (keep the overwrite same-length), or drop\n"
        "       this override (see patched-claude-code.nix).\n"
        "================================================================================\n"
    )
    sys.exit(1)


path = sys.argv[1]
with open(path, "rb") as f:
    data = f.read()

original_len = len(data)
count = data.count(ANCHOR)
if count != 1:
    die(f"expected 1 occurrence of the submit guard anchor in {path}, found {count}.")

data = data.replace(ANCHOR, REPLACEMENT)
assert len(data) == original_len, "overwrite must preserve byte length"

with open(path, "wb") as f:
    f.write(data)

print("patched submit guard -> always interrupt on mid-turn submit", file=sys.stderr)
