#!/usr/bin/env python3
"""Repurpose claude-code's `chat:stash` handler into "submit current input as a real
user turn, then exit".

Context: there is no one-key way to take what you've typed, persist it as a user turn,
and quit. Ctrl+C when idle just clears/keeps the input; `app:interrupt` is hardcoded and
there is no `submit-then-exit` action to bind. Config alone can't express it, so we patch
the binary: overwrite the stash callback (in the chat-input component) with
`onSubmit(draft.value);process.exit(0)` — the component receives both as props, so the
callback can submit exactly as Enter does. The user then rebinds `chat:stash` to `alt+a`
via keybindings.json.

Same-length overwrite (the replacement is shorter, padded with trailing spaces) so Bun's
compiled-ELF trailer offsets stay valid — same technique as strip-claude-reminders.py.

The anchor's occurrence count is asserted so the build fails LOUDLY if upstream changes
the minified wording.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-altexit.py (in your nix config)"

# The stash callback plus its React-Compiler memo-cache guard, verbatim from
# claude-code 2.1.280. In `R0e` (the chat-input component) `E` is the draft and `Be` is
# the `onSubmit` prop — the same closure, so submit is reachable from here.
# Must occur exactly once.
ANCHOR = b'if(nr[288]!==uf||nr[289]!==E||nr[290]!==Wr)jC=()=>{if(E.value.trim()===""&&E.stashedPrompt!==void 0)E.popStash("input"),uf(),_("input_stash");else if(E.value.trim()!=="")E.stash(),uf(),ke(xNt,Wr),_("input_stash")},nr[288]=uf,nr[289]=E,nr[290]=Wr,nr[291]=jC;else jC=nr[291]'

# The whole memoized block is replaced by a bare assignment: recomputing the closure on
# every render keeps `Be` fresh. `Be` is not among the cache's dependency slots, so
# leaving the memo in place could hand us a stale `onSubmit`.
# NB: process.exit(0) directly after submit kills the process before the user turn is
# flushed to the session transcript (the write happens on a later event-loop tick, after
# React effects). Defer the exit so the append lands first — verified by pty test that a
# synchronous exit drops the turn and a deferred one persists it. 800ms is comfortably
# above the observed write latency; it's the visible "submitting…" delay before quit.
REPLACEMENT = b'jC=()=>{Be(E.value);setTimeout(()=>process.exit(0),800)}'.ljust(len(ANCHOR))


def die(msg: str) -> None:
    sys.stderr.write(
        "\n"
        "================================================================================\n"
        "  claude-code alt-exit (submit+exit) patch FAILED\n"
        "================================================================================\n"
        f"  {msg}\n"
        "\n"
        "  This patch repurposes the `chat:stash` handler into submit-then-exit so\n"
        "  alt+a (rebound in keybindings.json) commits the input as a user turn and quits.\n"
        "  Upstream has likely changed the minified callback or its variable names.\n"
        "\n"
        "  To fix:\n"
        f"    1. Edit {THIS_FILE}\n"
        "    2. Inspect the binary (bin/.claude-unwrapped) for the stash callback — it is\n"
        '       the closure containing two `_("input_stash")` calls; take its enclosing\n'
        "       `if(nr[N]!==...)...else X=nr[M]` memo block whole.\n"
        "       Its component destructures `draft:` and `onSubmit:`; those two minified\n"
        "       names are what the replacement body needs.\n"
        "    3. Update ANCHOR / REPLACEMENT to match, keeping the overwrite same-length,\n"
        "       or drop this override (see patched-claude-code.nix).\n"
        "================================================================================\n"
    )
    sys.exit(1)


assert len(REPLACEMENT) == len(ANCHOR), "same-length overwrite required"

path = sys.argv[1]
with open(path, "rb") as f:
    data = f.read()

original_len = len(data)
count = data.count(ANCHOR)
if count != 1:
    die(f"expected 1 occurrence of the stash-callback anchor in {path}, found {count}.")

data = data.replace(ANCHOR, REPLACEMENT)
assert len(data) == original_len, "overwrite must preserve byte length"

with open(path, "wb") as f:
    f.write(data)

print("patched stash callback → submit+exit", file=sys.stderr)
