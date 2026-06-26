#!/usr/bin/env python3
"""Repurpose claude-code's `chat:stash` handler into "submit current input as a real
user turn, then exit".

Context: there is no one-key way to take what you've typed, persist it as a user turn,
and quit. Ctrl+C when idle just clears/keeps the input; `app:interrupt` is hardcoded and
there is no `submit-then-exit` action to bind. Config alone can't express it, so we patch
the binary: overwrite the body of the `vy` stash callback (in the chat-input component)
with `FH.current?.(tH.current);process.exit(0)` — `FH.current` is the onSubmit callback
and `tH.current` the current input, both in closure (same scope as `chat:submit`, whose
handler is literally `()=>{FH.current?.(tH.current)}`). The user then rebinds `chat:stash`
to `alt+a` via keybindings.json.

Same-length overwrite (the replacement is shorter, padded with trailing spaces) so Bun's
compiled-ELF trailer offsets stay valid — same technique as strip-claude-reminders.py.

The anchor's occurrence count is asserted so the build fails LOUDLY if upstream changes
the minified wording.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-altexit.py (in your nix config)"

# The `vy` stash callback, verbatim from claude-code 2.1.154. Prefix/suffix (the
# `useCallback` wrapper and its deps array) are preserved; only the inner `{...}` body
# is replaced. Must occur exactly once.
ANCHOR = b'vy=Jq.useCallback(()=>{if(e.trim()===""&&P!==void 0)_$(P.text),UH(P.cursorOffset),E(P.pastedContents),Z(void 0),SH("input_stash");else if(e.trim()!=="")Z({text:e,cursorOffset:NH,pastedContents:v}),_$(""),UH(0),E({}),O8((k$)=>{if(k$.hasUsedStash)return k$;return{...k$,hasUsedStash:!0}}),SH("input_stash")},[e,NH,P,_$,Z,v,E])'

PREFIX = b'vy=Jq.useCallback(()=>{'
SUFFIX = b'},[e,NH,P,_$,Z,v,E])'
# NB: process.exit(0) directly after submit kills the process before the user turn is
# flushed to the session transcript (the write happens on a later event-loop tick, after
# React effects). Defer the exit so the append lands first — verified by pty test that a
# synchronous exit drops the turn and a deferred one persists it. 800ms is comfortably
# above the observed write latency; it's the visible "submitting…" delay before quit.
NEW_BODY = b'FH.current?.(tH.current);setTimeout(()=>process.exit(0),800)'


def die(msg: str) -> None:
    sys.stderr.write(
        "\n"
        "================================================================================\n"
        "  claude-code alt-exit (submit+exit) patch FAILED\n"
        "================================================================================\n"
        f"  {msg}\n"
        "\n"
        "  This patch repurposes the `chat:stash` (vy) handler into submit-then-exit so\n"
        "  alt+a (rebound in keybindings.json) commits the input as a user turn and quits.\n"
        "  Upstream has likely changed the minified `vy` callback or its variable names.\n"
        "\n"
        "  To fix:\n"
        f"    1. Edit {THIS_FILE}\n"
        "    2. Inspect the binary (bin/.claude-unwrapped) for the stash callback:\n"
        "         grep -ao 'vy=Jq.useCallback[^]]*hasUsedStash[^]]*])' <claude-binary>\n"
        "       and the submit closure (confirms FH/tH names):\n"
        "         grep -ac 'FH.current?.(tH.current)' <claude-binary>\n"
        "    3. Update ANCHOR / PREFIX / SUFFIX / NEW_BODY to match, keeping the overwrite\n"
        "       same-length, or drop this override (see patched-claude-code.nix).\n"
        "================================================================================\n"
    )
    sys.exit(1)


assert ANCHOR.startswith(PREFIX) and ANCHOR.endswith(SUFFIX), "PREFIX/SUFFIX must frame ANCHOR"
inner_len = len(ANCHOR) - len(PREFIX) - len(SUFFIX)
if len(NEW_BODY) > inner_len:
    die(f"replacement body ({len(NEW_BODY)}B) longer than original inner body ({inner_len}B)")
REPLACEMENT = PREFIX + NEW_BODY + b" " * (inner_len - len(NEW_BODY)) + SUFFIX
assert len(REPLACEMENT) == len(ANCHOR), "same-length overwrite required"

path = sys.argv[1]
with open(path, "rb") as f:
    data = f.read()

original_len = len(data)
count = data.count(ANCHOR)
if count != 1:
    die(f"expected 1 occurrence of the `vy` stash anchor in {path}, found {count}.")

data = data.replace(ANCHOR, REPLACEMENT)
assert len(data) == original_len, "overwrite must preserve byte length"

with open(path, "wb") as f:
    f.write(data)

print("patched vy → submit+exit", file=sys.stderr)
