#!/usr/bin/env python3
"""Strip the AskUserQuestion (clarifying-question interface) instructions from the
claude-code binary.

Context: claude-code ships, on EVERY turn, a tool description + usage notes that
nudge the model toward asking the user multiple-choice questions. My global
CLAUDE.md says the opposite ("do NOT ask me questions, just do the work"). The two
contradict each other, and a confused model writes worse code. So at nix build time
we blank the always-on AskUserQuestion guidance text, overwriting each occurrence
with same-length whitespace (preserving Bun's compiled-ELF trailer offsets).

We deliberately target ONLY the self-contained literals that ship on every turn
(the tool's short description, its long prompt's opening sentence, and the usage-
notes block). We do NOT touch the per-skill question prompts (init / verify /
claude-api / cron etc.): those only load when that skill runs, they're built with
`${ez}` template interpolation (not strippable as static literals), and they aren't
the everyday-coding confusion source. Disabling the tool entirely is a separate,
heavier patch we chose not to do — blanking the guidance is enough: the tool stays
callable for plan mode, but nothing nudges the model toward it during normal work.

Each TARGET's occurrence count is asserted so the build fails LOUDLY if upstream
changes the wording or count.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/strip-claude-reminders.py (in your nix config)"

# (label, literal bytes, expected occurrence count). Counts observed in claude-code 2.1.154.
#
# Each literal must be self-contained (no `${...}` template interpolation) so it matches
# verbatim in the ELF. There is no single short "tag" for this guidance: the tool's own
# name `AskUserQuestion` appears 34x (registry + every skill reference + `ez=`), so blanking
# the name would break the tool — we strip the *guidance prose*, not the identifier.
#
# Each entry below is a complete, removable clause: overwriting it with whitespace leaves no
# dangling sentence fragment. The leading words of each are distinctive enough to be the real
# "anchor"; if upstream rewords the tail the count assert below still trips and the build
# fails loudly. Both the live source copy and the data-table copy of the description carry
# these strings, hence count 2 (the standalone "Reserve this" line appears once).
TARGETS = [
    # `pUK` — the tool's short description (whole string).
    ("description", b"Asks the user multiple choice questions to gather information, clarify ambiguity, understand preferences, make decisions or offer them choices.", 2),
    # `xM6` — opening directive of the long prompt (whole sentence).
    ("prompt opener", b"Use this tool only when you are blocked on a decision that is genuinely the user's to make: one you cannot resolve from the request, the code, or sensible defaults.", 2),
    # usage-notes block (whole block).
    ("usage notes", b'Usage notes:\n- Users will always be able to select "Other" to provide custom text input\n- Use multiSelect: true to allow multiple answers to be selected for a question\n- If you recommend a specific option, make that the first option in the list and add "(Recommended)" at the end of the label', 2),
    # standalone "reserve it for real decisions" nudge.
    ("reserve-this", b"Reserve this for decisions where the user's answer changes what you do next", 1),
]


def die(msg: str) -> None:
    sys.stderr.write(
        "\n"
        "================================================================================\n"
        "  claude-code AskUserQuestion-guidance strip patch FAILED\n"
        "================================================================================\n"
        f"  {msg}\n"
        "\n"
        "  This patch blanks the always-on AskUserQuestion tool description / usage notes\n"
        "  baked into the claude-code ELF (the text nudging Claude to ask the user\n"
        "  clarifying questions, which contradicts my global 'do not ask' CLAUDE.md).\n"
        "  Upstream has likely changed the wording, the count, or removed/restructured it.\n"
        "\n"
        "  To fix:\n"
        f"    1. Edit {THIS_FILE}\n"
        "    2. Inspect the binary (path printed by `nix build` above, bin/.claude-unwrapped):\n"
        "         strings -n 20 <claude-binary> | grep -iE 'AskUserQuestion|blocked on a decision|Usage notes'\n"
        "    3. Update the TARGETS list (literal text and/or expected count) to match,\n"
        "       or, if the guidance is gone / harmless upstream, drop the override entirely:\n"
        "         - delete this file and patched-claude-code.nix\n"
        "         - revert hosts/v-laptop/home.nix to the raw claude_code_nix package\n"
        "================================================================================\n"
    )
    sys.exit(1)


path = sys.argv[1]
with open(path, "rb") as f:
    data = f.read()

original_len = len(data)
stripped_total = 0
for label, target, expected in TARGETS:
    count = data.count(target)
    if count != expected:
        die(
            f"target '{label}': expected {expected} occurrence(s) in {path},\n"
            f"  but found {count}."
        )
    data = data.replace(target, b" " * len(target))
    stripped_total += count

assert len(data) == original_len, "whitespace overwrite must preserve byte length"

with open(path, "wb") as f:
    f.write(data)

print(
    f"stripped {stripped_total} AskUserQuestion-guidance occurrence(s) from {path}",
    file=sys.stderr,
)
