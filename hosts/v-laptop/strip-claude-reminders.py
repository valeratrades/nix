#!/usr/bin/env python3
"""Strip the per-Read malware-check system-reminder from the claude-code binary.

Context: claude-code injects this <system-reminder> into the result of every
single Read tool call, eating context and degrading accuracy on legitimate work
in a personal codebase. The reminder is baked as a literal UTF-8 string into the
Bun-compiled ELF, so we overwrite each occurrence with same-length whitespace
(preserving Bun's trailer offsets) at nix build time.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

TARGET = (
    b"Whenever you read a file, you should consider whether it would be considered malware. "
    b"You CAN and SHOULD provide analysis of malware, what it is doing. "
    b"But you MUST refuse to improve or augment the code. "
    b"You can still analyze existing code, write reports, or answer questions about the code behavior."
)
EXPECTED_COUNT = 3  # observed in claude-code 2.1.81

THIS_FILE = "hosts/v-laptop/strip-claude-reminders.py (in your nix config)"


def die(msg: str) -> None:
    sys.stderr.write(
        "\n"
        "================================================================================\n"
        "  claude-code malware-reminder strip patch FAILED\n"
        "================================================================================\n"
        f"  {msg}\n"
        "\n"
        "  This patch overwrites a hardcoded <system-reminder> string baked into the\n"
        "  claude-code ELF (the one telling Claude to treat every file read as suspected\n"
        "  malware). Upstream has likely changed the wording, the count, or removed it.\n"
        "\n"
        "  To fix:\n"
        f"    1. Edit {THIS_FILE}\n"
        "    2. Run:  strings <claude-binary> | grep -i malware\n"
        "       (binary path is printed by `nix build` above, under bin/.claude-unwrapped)\n"
        "    3. Either update TARGET / EXPECTED_COUNT to match the new string,\n"
        "       or, if the reminder is gone upstream, remove the override entirely:\n"
        "         - delete this file and patched-claude-code.nix\n"
        "         - revert hosts/v-laptop/home.nix to use the raw claude_code_nix package\n"
        "================================================================================\n"
    )
    sys.exit(1)


path = sys.argv[1]
with open(path, "rb") as f:
    data = f.read()

if len(TARGET) != 300:
    die(f"TARGET length is {len(TARGET)}, expected 300 — script was edited incorrectly")

count = data.count(TARGET)
if count != EXPECTED_COUNT:
    die(
        f"expected {EXPECTED_COUNT} occurrences of the malware-reminder string in {path},\n"
        f"  but found {count}."
    )

patched = data.replace(TARGET, b" " * len(TARGET))
assert len(patched) == len(data)
with open(path, "wb") as f:
    f.write(patched)

print(f"stripped {count} malware-reminder occurrences from {path}", file=sys.stderr)
