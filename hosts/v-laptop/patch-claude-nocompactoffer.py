#!/usr/bin/env python3
"""Never show the "We recommend compacting earlier" dialog (the `autocompact-offer` prompt that proposes autocompacting at 400k).

The offer's setup bails out when the session is remote/disabled/mid-turn; the remote flag is pinned to true.

Same-length overwrite so Bun's compiled-ELF trailer offsets stay valid; takes effect only through
detach-claude-bytecode.py. Anchor is verbatim from claude-code 2.1.326; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-nocompactoffer.py (in your nix config)"
HINT = "grep -ao '.\\{0,120\\}tengu_autocompact_offer_eligible' <binary>   # then walk back to the `if(...)return;let po=...` guard"

ANCHOR = b'if(St||Et||Je||Rt>0||Lt||mt!==null||et!=="completed")return;let po=X0t({transcript:it,mainLoopModel:Ft});if(po<Ote)return;'
REPLACEMENT = ANCHOR.replace(b"if(St||", b"if(!0||", 1)

path = sys.argv[1]
with open(path, "rb") as f:
	data = f.read()
original_len = len(data)

count = data.count(ANCHOR)
if count != 1:
	sys.stderr.write(
		"\n"
		"================================================================================\n"
		"  claude-code no-compact-offer patch FAILED\n"
		"================================================================================\n"
		f"  expected 1 occurrence of the anchor in {path}, found {count}.\n"
		"\n"
		"  Upstream has likely changed the minified code or its variable names.\n"
		f"  1. Edit {THIS_FILE}\n"
		f"  2. Locate the new spelling:\n"
		f"       {HINT}\n"
		"  3. Update ANCHOR (same-length overwrite), or drop the patch if the offer is gone.\n"
		"================================================================================\n"
	)
	sys.exit(1)
data = data.replace(ANCHOR, REPLACEMENT)
print("patched autocompact offer", file=sys.stderr)

assert len(data) == original_len, "overwrite must preserve byte length"
with open(path, "wb") as f:
	f.write(data)
