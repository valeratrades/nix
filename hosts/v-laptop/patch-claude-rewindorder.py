#!/usr/bin/env python3
"""Rewind dialog: "Restore conversation" first and focused, "Restore code and conversation" second.

A stray Enter on the rewind dialog should not also roll back files.

Same-length overwrite (padded with spaces) so Bun's compiled-ELF trailer offsets stay valid;
takes effect only through detach-claude-bytecode.py. Anchors are verbatim from claude-code
2.1.303; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-rewindorder.py (in your nix config)"

PATCHES = [
	(
		"rewind options order",
		"grep -ao '.\\{0,60\\}function [A-Za-z0-9_$]*([A-Za-z0-9_$]*){let [A-Za-z0-9_$]*=[A-Za-z0-9_$]*?\\[{value:\"both\".\\{0,200\\}'",
		b'[Qo,so]=y("both"),[po,jo]=y(""),[Jo,Cn]=y("");function Po($o){let mn=$o?['
		b'{value:"both",label:"Restore code and conversation"},{value:"conversation",label:"Restore conversation"},'
		b'{value:"code",label:"Restore code"}]:[{value:"conversation",label:"Restore conversation"}],',
		b'[Qo,so]=y("conversation"),[po,jo]=y(""),[Jo,Cn]=y("");function Po($o){'
		b'let rc={value:"conversation",label:"Restore conversation"},mn=$o?['
		b'rc,{value:"both",label:"Restore code and conversation"},{value:"code",label:"Restore code"}]:[rc],',
	),
	(
		"rewind default focus",
		"grep -ao 'defaultFocusValue:[A-Za-z0-9_$]*?\"both\":\"conversation\"'",
		b'defaultFocusValue:xn?"both":"conversation"',
		b'defaultFocusValue:"conversation"',
	),
]


def die(name: str, hint: str, msg: str) -> None:
	sys.stderr.write(
		"\n"
		"================================================================================\n"
		f"  claude-code rewind-order patch FAILED: {name}\n"
		"================================================================================\n"
		f"  {msg}\n"
		"\n"
		"  Upstream has likely changed the minified code or its variable names.\n"
		f"  1. Edit {THIS_FILE}\n"
		f"  2. Locate the new spelling in bin/.claude-unwrapped:\n"
		f"       {hint} <binary>\n"
		"  3. Update the anchor/replacement (same-length overwrite; trim the replacement if\n"
		"     it outgrew the anchor), or drop the patch if upstream reordered the options.\n"
		"================================================================================\n"
	)
	sys.exit(1)


path = sys.argv[1]
with open(path, "rb") as f:
	data = f.read()
original_len = len(data)

for name, hint, anchor, replacement in PATCHES:
	if len(replacement) > len(anchor):
		die(name, hint, f"replacement is {len(replacement) - len(anchor)} bytes longer than the anchor.")
	count = data.count(anchor)
	if count != 1:
		die(name, hint, f"expected 1 occurrence of the anchor in {path}, found {count}.")
	data = data.replace(anchor, replacement.ljust(len(anchor)))
	print(f"patched {name}", file=sys.stderr)

assert len(data) == original_len, "overwrite must preserve byte length"
with open(path, "wb") as f:
	f.write(data)
