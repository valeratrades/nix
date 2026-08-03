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

Fix: neutralize the `hasInterruptibleToolInProgress` gate so the abort always fires, AND
abort with reason `"user-cancel"` rather than upstream's `"interrupt"`.

The reason string is load-bearing, do not "restore" it on a version bump. Since 2.1.220
abort reasons are memoized DOMException singletons (`VC`) and both turn teardown and the
Bash tool branch on them: `"interrupt"` is classified as a soft reason that neither tears
down a running Bash tool nor surfaces the interrupt message, yet it still latches the
AbortController into the aborted state. `AbortController.abort()` on an already-aborted
controller is a spec no-op, so the Esc handler's `abort(VC("user-cancel"))` can never
fire again for the rest of that turn: the session hangs on a spinner, queued prompts get
bounced back into the input box, and Esc/Ctrl-C do nothing. `"user-cancel"` is the reason
the Esc handler itself uses and tears the turn down cleanly.

Same-length overwrite (replacement padded with spaces) so Bun's compiled-ELF trailer
offsets stay valid — same technique as strip-claude-reminders.py / patch-claude-altexit.py.

The anchor's occurrence count is asserted so the build fails LOUDLY if upstream changes
the minified wording.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-queuejoin.py (in your nix config)"

# The mid-turn submit guard, verbatim from claude-code 2.1.220. Must occur exactly once.
COND = b'e.hasInterruptibleToolInProgress'
BODY = (b'){w(`[interrupt] Aborting current turn: streamMode=${e.streamMode}`);'
        b'let j=nN(u,g().effortValue);O("tengu_cancel",{source:Ee("interrupt_on_submit"),'
        b'streamMode:Xo(e.streamMode),...j&&{effort_level:fe(j)}}),'
        b'e.abortController?.abort(VC("interrupt"))}')
ANCHOR = b'if(' + COND + BODY
NEW_BODY = BODY.replace(b'VC("interrupt")', b'VC("user-cancel")')
REPLACEMENT = b'if(true' + b' ' * (len(ANCHOR) - len(b'if(true') - len(NEW_BODY)) + NEW_BODY
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
        "  (instead of folding into it when no tool is executing), aborting with reason\n"
        '  "user-cancel" — "interrupt" leaves the controller latched and kills Esc.\n'
        "  Upstream has likely changed the minified submit guard or its variable names.\n"
        "\n"
        "  To fix:\n"
        f"    1. Edit {THIS_FILE}\n"
        "    2. Find the mid-turn submit branch in bin/.claude-unwrapped:\n"
        "         grep -ao 'hasInterruptibleToolInProgress[^}]*abort([^)]*)' <binary>\n"
        "    3. Update COND/BODY to match (keep the overwrite same-length, and keep the\n"
        '       abort reason as whatever the Esc handler uses — "user-cancel" on 2.1.220),\n'
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
