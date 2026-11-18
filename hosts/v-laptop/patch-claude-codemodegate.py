#!/usr/bin/env python3
"""Let Code Mode's start-up check take the account's saved feature-flag answer, not only one fetched this launch.

Stock requires the gate to come from a payload fetched within 5s of start; a slow or contended start (restore_sessions
launching every claude at once) misses that, declares the account not in the rollout, restarts without Code Mode,
and a Code Mode session then refuses to resume. The saved answer is still the server's, from the last fetch.

Same-length overwrite so Bun's compiled-ELF trailer offsets stay valid; takes effect only through
detach-claude-bytecode.py. Anchor is verbatim from claude-code 2.1.326; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-codemodegate.py (in your nix config)"
HINT = "grep -ao '.\\{0,200\\}if(!W())return\"gate\"' <binary>   # W is the function returning e===!0&&(n===\"payload\"||...)"

ANCHOR = b'function W(){let{value:e,source:n}=dn(zWi,!1);return e===!0&&(n==="payload"||n==="override")}'
REPLACEMENT = ANCHOR.replace(b'n==="override")', b'n==="disk"    )', 1)

path = sys.argv[1]
with open(path, "rb") as f:
	data = f.read()
original_len = len(data)

count = data.count(ANCHOR)
if count != 1:
	sys.stderr.write(
		"\n"
		"================================================================================\n"
		"  claude-code code-mode-gate patch FAILED\n"
		"================================================================================\n"
		f"  expected 1 occurrence of the anchor in {path}, found {count}.\n"
		"\n"
		"  Upstream has likely changed the minified code or its variable names.\n"
		f"  1. Edit {THIS_FILE}\n"
		f"  2. Locate the new spelling:\n"
		f"       {HINT}\n"
		"  3. Update ANCHOR (same-length overwrite), or drop the patch if the check no longer demands a fresh payload.\n"
		"================================================================================\n"
	)
	sys.exit(1)
data = data.replace(ANCHOR, REPLACEMENT)
print("patched code mode gate", file=sys.stderr)

assert len(data) == original_len, "overwrite must preserve byte length"
with open(path, "wb") as f:
	f.write(data)
