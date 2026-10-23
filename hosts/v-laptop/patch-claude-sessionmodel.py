#!/usr/bin/env python3
"""`/model` and `/effort` switch the current session only, never the saved default in settings.json.

1. Picker Enter. It called onSetDefault before applying the pick; now it applies only,
   same as the picker's built-in `s` (use this session only). Covers both pickers that
   render the shared model-picker component (`/model` and the footer one).

2. Inline `/model <name>`. Persisting was gated on the session being interactive; the gate
   is pinned to false.

Same-length overwrite (padded with spaces) so Bun's compiled-ELF trailer offsets stay valid;
takes effect only through detach-claude-bytecode.py. Anchors are verbatim from claude-code
2.1.303; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-sessionmodel.py (in your nix config)"

PATCHES = [
	(
		"model picker enter",
		"grep -ao 'function [A-Za-z0-9_$]*([A-Za-z0-9_$]*){if([A-Za-z0-9_$]*)[A-Za-z0-9_$]*([A-Za-z0-9_$]*===[A-Za-z0-9_$]*?null:[A-Za-z0-9_$]*);[A-Za-z0-9_$]*([A-Za-z0-9_$]*)}'",
		b'function dr(Kn){if(H)H(Kn===tS?null:Kn);Ir(Kn)}',
		b'function dr(Kn){Ir(Kn)}',
	),
	(
		"inline /model <name>",
		"grep -ao '=([A-Za-z0-9_$]*,[A-Za-z0-9_$]*)=>{let [A-Za-z0-9_$]*=![A-Za-z0-9_$]*();[A-Za-z0-9_$]*(null);.\\{0,80\\}\"command\"'",
		b'Ee=(J,re)=>{let Se=!Tt();z(null);',
		b'Ee=(J,re)=>{let Se=!1;z(null);',
	),
	(
		"effort writer",
		"grep -ao 'let [A-Za-z0-9_$]*=[A-Za-z0-9_$]*!==void 0?[A-Za-z0-9_$]*([A-Za-z0-9_$]*):void 0;if([A-Za-z0-9_$]*&&([A-Za-z0-9_$]*===void 0||'",
		b'let d=e!==void 0?pEe(e):void 0;if(r&&(e===void 0||d!==void 0)&&!Cr())',
		b'let d=e!==void 0?pEe(e):void 0;if(0&&(e===void 0||d!==void 0)&&!Cr())',
	),
	(
		"/effort persist flag",
		"grep -ao 'async function [A-Za-z0-9_$]*([A-Za-z0-9_$,]*=!0,[A-Za-z0-9_$]*){let [A-Za-z0-9_$]*=!1,[A-Za-z0-9_$]*=null,[A-Za-z0-9_$]*=await [A-Za-z0-9_$]*([A-Za-z0-9_$,]*('",
		b'E=await P(e,t,r,(d)=>',
		b'E=await P(e,t,0,(d)=>',
	),
]


def die(name: str, hint: str, msg: str) -> None:
	sys.stderr.write(
		"\n"
		"================================================================================\n"
		f"  claude-code session-model patch FAILED: {name}\n"
		"================================================================================\n"
		f"  {msg}\n"
		"\n"
		"  Upstream has likely changed the minified code or its variable names.\n"
		f"  1. Edit {THIS_FILE}\n"
		f"  2. Locate the new spelling in bin/.claude-unwrapped:\n"
		f"       {hint} <binary>\n"
		"  3. Update the anchor/replacement (same-length overwrite), or drop the entry if\n"
		"     upstream made /model or /effort session-scoped by default.\n"
		"================================================================================\n"
	)
	sys.exit(1)


path = sys.argv[1]
with open(path, "rb") as f:
	data = f.read()
original_len = len(data)

for name, hint, anchor, replacement in PATCHES:
	assert len(replacement) <= len(anchor), name
	count = data.count(anchor)
	if count != 1:
		die(name, hint, f"expected 1 occurrence of the anchor in {path}, found {count}.")
	data = data.replace(anchor, replacement.ljust(len(anchor)))
	print(f"patched {name}", file=sys.stderr)

assert len(data) == original_len, "overwrite must preserve byte length"
with open(path, "wb") as f:
	f.write(data)
