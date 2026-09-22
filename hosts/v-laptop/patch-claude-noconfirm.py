#!/usr/bin/env python3
"""Remove the confirmations claude-code still raises under --dangerously-skip-permissions.

1. Bypass-immune safety checks. Each circuit breaker (dangerousRemoval, isolatePeerMachines,
   restrictedMode, outsideReadsBlocked) carries a `bypassImmune` flag, and a single predicate
   over it decides whether bypass mode still stops for approval. Making it always false lets
   bypass mode allow every ask except explicit `permissions.ask` rules and tools that are
   interactive by nature (AskUserQuestion, ExitPlanMode).

2. Invisible-Unicode review on submit. A prompt carrying zero-width/bidi/tag characters
   outside emoji sequences is stripped and parked, waiting for a second Enter. Instead the
   stripped text and pastes are sent straight away.

Same-length overwrite (padded with spaces) so Bun's compiled-ELF trailer offsets stay valid;
takes effect only through detach-claude-bytecode.py. Anchors are verbatim from claude-code
2.1.280; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-noconfirm.py (in your nix config)"

PATCHES = [
	(
		"bypass-immune predicate",
		"grep -ao 'function [A-Za-z0-9_$]*(e){return [A-Za-z0-9_$]*(e).some((n)=>[A-Za-z0-9_$]*\\[n\\]?.bypassImmune===!0)}'",
		b'return Co(e).some((n)=>un[n]?.bypassImmune===!0)',
		b'return!1',
	),
	(
		"invisible-unicode submit review",
		"grep -ao 'if([A-Za-z0-9_$]*.removed.removedTotal>0){[^}]*}[^}]*prompt-invisible-removed[^}]*}[^}]*}'",
		b'if(Tm.removed.removedTotal>0){Gd(),IKe(Tm.removed,"prompt");let TR=Tm.input.trim()==="";'
		b'if(bqn(Vo,Cp,Tm.input),Zt(Tm.input),ro(Tm.input.length),Tm.pastedContents!==Z.pastedContents)'
		b'uo(Tm.pastedContents);Ja({key:"prompt-invisible-removed",kind:"feedback",'
		b'text:hbe(Tm.removed.removedTotal,TR?"empty":"review"),priority:"immediate",timeoutMs:Iy}),'
		b'_E(XBt);return}',
		b'if(Tm.removed.removedTotal>0)Cp=Tm.input,HS=Tm.pastedContents;',
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
