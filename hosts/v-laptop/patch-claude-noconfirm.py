#!/usr/bin/env python3
"""Remove the confirmations claude-code still raises under --dangerously-skip-permissions.

1. Bypass-immune safety checks. Each circuit breaker (dangerousRemoval, isolatePeerMachines,
   restrictedMode, outsideReadsBlocked) carries a `bypassImmune` flag, and a single predicate
   over it decides whether bypass mode still stops for approval. Making it always false lets
   bypass mode allow every ask except explicit `permissions.ask` rules and tools that are
   interactive by nature (AskUserQuestion, ExitPlanMode).

2. Invisible-Unicode review on submit. A prompt carrying zero-width/bidi/tag characters
   outside emoji sequences is stripped; upstream sends the cleaned text on, except when its
   review predicate (bidi removed, empty, `/` or `!` prefix, non-prompt mode) parks it for a
   second Enter. The predicate is pinned false, so the stripped text and pastes always go.

3. "Switch model?" cache-miss dialog. Raised on a model switch while the prompt cache is
   warm; its predicate now always says no.

Same-length overwrite (padded with spaces) so Bun's compiled-ELF trailer offsets stay valid;
takes effect only through detach-claude-bytecode.py. Anchors are verbatim from claude-code
2.1.326; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-noconfirm.py (in your nix config)"

PATCHES = [
	(
		"bypass-immune predicate",
		"grep -ao 'function [A-Za-z0-9_$]*(e){return [A-Za-z0-9_$]*(e).some(([a-z])=>[A-Za-z0-9_$]*\\[[a-z]\\]?.bypassImmune===!0)}'",
		b'return d(e).some((o)=>XNe[o]?.bypassImmune===!0)',
		b'return!1',
	),
	(
		"invisible-unicode submit review",
		"grep -ao 'let [A-Za-z0-9_$]*=[A-Za-z0-9_$]*.input.trim()===\"\";let [A-Za-z0-9_$]*=[A-Za-z0-9_$]*([A-Za-z0-9_$]*.input,[A-Za-z0-9_$]*.removed,[A-Za-z0-9_$]*.mode);'",
		b'let Gae=Gf.input.trim()==="";let xT=Szn(Gf.input,Gf.removed,ee.mode);',
		b'let Gae=Gf.input.trim()==="";let xT=!1;',
	),
	(
		"model-switch cache-miss dialog",
		"grep -ao 'function [A-Za-z0-9_$]*(e,o,[a-z],[a-z],n){if(n===void 0)return!1;.\\{0,240\\}has([a-z])===!0))}'",
		(b'function zEo(e,o,r,a,n){if(n===void 0)return!1;let l=lb();if(l===0||l===a)return!1;let i=Kn(IZ(e));if(i===Kn(I'
		  b'Z(P_e({mainLoopModel:o,mainLoopModelForSession:r}))))return!1;let u=n.response?.message.model;return!(typeof u'
		  b'==="string"&&(u===i||pmr(i)?.has(u)===!0))}'),
		b'function zEo(){return!1}',
	),
]


def die(name: str, hint: str, msg: str) -> None:
	sys.stderr.write(
		"\n"
		"================================================================================\n"
		f"  claude-code no-confirm patch FAILED: {name}\n"
		"================================================================================\n"
		f"  {msg}\n"
		"\n"
		"  Upstream has likely changed the minified code or its variable names.\n"
		f"  1. Edit {THIS_FILE}\n"
		f"  2. Locate the new spelling in bin/.claude-unwrapped:\n"
		f"       {hint} <binary>\n"
		"  3. Update the anchor/replacement (same-length overwrite), or drop the entry if\n"
		"     upstream no longer raises that confirmation.\n"
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
