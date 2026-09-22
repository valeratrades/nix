#!/usr/bin/env python3
"""Force claude-code to ALWAYS interrupt the current turn when you submit while it's
busy, instead of silently folding your new prompt into the in-progress exchange.

Context: when you submit a prompt while a turn is live, claude-code enqueues it and lets
it ride along with the ongoing exchange. On 2.1.220 there was at least a partial abort,
gated on `hasInterruptibleToolInProgress` (true only while a tool actually executes); as
of 2.1.280 that gate is gone entirely and the submit branch (`if(guard.isActive||
isExternalLoading)`) only ever enqueues. We want every mid-turn submit to be a hard
interrupt that starts a fresh turn; rolling back to edit the previous message is an
explicit Esc, not an implicit side effect of typing fast.

Fix: call the turn's own `interruptForSubmit()` on entry to that branch, after its two
early returns. It aborts the live controller with reason `"user-cancel"` and no-ops when
there is nothing in flight; the existing enqueue then drains into a fresh turn.

The reason string is load-bearing, do not "restore" it to `"interrupt"` if a future
version reintroduces a choice. Abort reasons are memoized DOMException singletons and
both turn teardown and the Bash tool branch on them: `"interrupt"` is classified as a
soft reason that neither tears down a running Bash tool nor surfaces the interrupt
message, yet it still latches the AbortController into the aborted state.
`AbortController.abort()` on an already-aborted controller is a spec no-op, so the Esc
handler's `abort("user-cancel")` could never fire again for the rest of that turn: the
session hangs on a spinner, queued prompts get bounced back into the input box, and
Esc/Ctrl-C do nothing. Upstream's `interruptForSubmit` already uses `"user-cancel"`.

Same-length overwrite (replacement padded with spaces) so Bun's compiled-ELF trailer
offsets stay valid — same technique as strip-claude-reminders.py / patch-claude-altexit.py.
The byte budget for the inserted call is bought by dropping the `mode_not_queueable`
telemetry call on the adjacent early return; it is analytics only.

The anchor's occurrence count is asserted so the build fails LOUDLY if upstream changes
the minified wording.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-queuejoin.py (in your nix config)"

# Head of the mid-turn submit branch inside the submit helper (`q0`), verbatim from
# claude-code 2.1.280: `jt` is the turn guard, `qt` is isExternalLoading, `E` is the turn.
# Must occur exactly once.
ANCHOR = (b'if(jt.isActive||qt){if(ro!=="prompt"&&ro!=="bash"){'
          b'm("prompt_queued","mode_not_queueable");return}if(Yo())return;')
REPLACEMENT = (b'if(jt.isActive||qt){if(ro!=="prompt"&&ro!=="bash"){'
               b'return}if(Yo())return;E.interruptForSubmit();').ljust(len(ANCHOR))
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
        "  instead of folding into it, via the turn's own interruptForSubmit().\n"
        "  Upstream has likely changed the minified submit branch or its variable names.\n"
        "\n"
        "  To fix:\n"
        f"    1. Edit {THIS_FILE}\n"
        "    2. Find the mid-turn submit branch in bin/.claude-unwrapped: search for\n"
        '       \'"mode_not_queueable"\' — the enclosing `if(<guard>.isActive||<loading>){`\n'
        "       is the branch, and the submit helper's `turn` binding is the receiver.\n"
        "    3. Update ANCHOR/REPLACEMENT to match, keeping the overwrite same-length,\n"
        "       or drop this override (see patched-claude-code.nix).\n"
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
