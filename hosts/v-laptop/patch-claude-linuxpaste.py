#!/usr/bin/env python3
"""Let an empty terminal paste attach the clipboard image on Linux, as Ctrl+V does.

With only an image on the clipboard, a terminal paste (ctrl+shift+v, shift+insert, a clipboard
manager pasting through either) arrives as an empty bracketed paste. Claude's paste handler then
reads the clipboard image, but only on macOS/WSL; we drop that platform gate.

Same-length overwrite, see strip-claude-reminders.py.
Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-linuxpaste.py (in your nix config)"

# claude-code 2.1.303, paste handler `Cnt`: K = paste is empty, N/J = macOS/WSL, n = onImagePaste, U = debounced clipboard-image read
ANCHOR = b'if(K&&(N||J)&&n){U();return}'
REPLACEMENT = b'if(K&&n){U();return}'.ljust(len(ANCHOR))


def die(msg: str) -> None:
	sys.stderr.write(
		"\n"
		"================================================================================\n"
		"  claude-code linux empty-paste → image patch FAILED\n"
		"================================================================================\n"
		f"  {msg}\n"
		"\n"
		"  To fix:\n"
		f"    1. Edit {THIS_FILE}\n"
		"    2. Find the paste handler in bin/.claude-unwrapped: the function taking\n"
		'       `{onPaste:,handleKeyDown:,onImagePaste:}` that defines `O()==="macos"` and\n'
		'       `O()==="wsl"` memos; its empty-paste branch is the anchor.\n'
		"    3. Update ANCHOR / REPLACEMENT, or drop this patch (see patched-claude-code.nix).\n"
		"================================================================================\n"
	)
	sys.exit(1)


assert len(REPLACEMENT) == len(ANCHOR), "same-length overwrite required"

path = sys.argv[1]
with open(path, "rb") as f:
	data = f.read()

count = data.count(ANCHOR)
if count != 1:
	die(f"expected 1 occurrence of the empty-paste anchor in {path}, found {count}.")

patched = data.replace(ANCHOR, REPLACEMENT)
assert len(patched) == len(data), "overwrite must preserve byte length"

with open(path, "wb") as f:
	f.write(patched)

print("patched empty paste → clipboard image on linux", file=sys.stderr)
