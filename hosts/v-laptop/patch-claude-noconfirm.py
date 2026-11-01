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

3. "Switch model?" cache-miss dialog. Raised on any switch while the prompt cache is warm;
   now only once context has grown 10k tokens past the session's first response; an
   absolute threshold never skips, as a fresh session already carries ~45k of system prompt,
   memory, skills and hook output. Callers pass the app state and that first response in
   place of the two model fields.

Same-length overwrite (padded with spaces) so Bun's compiled-ELF trailer offsets stay valid;
takes effect only through detach-claude-bytecode.py. Anchors are verbatim from claude-code
2.1.303; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-noconfirm.py (in your nix config)"

PATCHES = [
	(
		"bypass-immune predicate",
		"grep -ao 'function [A-Za-z0-9_$]*(e){return [A-Za-z0-9_$]*(e).some(([a-z])=>[A-Za-z0-9_$]*\\[[a-z]\\]?.bypassImmune===!0)}'",
		b'return d(e).some((o)=>Fpn[o]?.bypassImmune===!0)',
		b'return!1',
	),
	(
		"invisible-unicode submit review",
		"grep -ao 'if([A-Za-z0-9_$]*.removed.removedTotal>0){[^}]*}[^}]*prompt-invisible-removed[^}]*}[^}]*}'",
		b'if(Wf.removed.removedTotal>0){xd(),cxt(Wf.removed,"prompt");let AL=Wf.input.trim()==="";'
		b'if(R6r(To,fc,Wf.input),no(Wf.input),eo(Wf.input.length),Wf.pastedContents!==ee.pastedContents)'
		b'co(Wf.pastedContents);cl({key:"prompt-invisible-removed",kind:"feedback",'
		b'text:NBe(Wf.removed.removedTotal,AL?"empty":"review"),priority:"immediate",timeoutMs:Rb}),'
		b'jx(xto);return}',
		b'if(Wf.removed.removedTotal>0)fc=Wf.input,Fw=Wf.pastedContents;',
	),
	(
		"model-switch cache-miss dialog",
		"grep -ao 'function [A-Za-z0-9_$]*(e,o,i,s,n){if(n===void 0)return!1;.\\{0,240\\}has(c)===!0))}'",
		b'function rcr(e,o,i,s,n){if(n===void 0)return!1;let l=kh();if(l===0||l===s)return!1;let r=Mn(Gce(e));'
		b'if(r===Mn(Gce(SZ({mainLoopModel:o,mainLoopModelForSession:i}))))return!1;let c=n.response?.message.model;'
		b'return!(typeof c==="string"&&(c===r||nhn(r)?.has(c)===!0))}',
		b'function rcr(e,o,i,s,n){let u=(m)=>(m=m?.message.usage)&&m.input_tokens+m.cache_read_input_tokens+m.cache_creation_input_tokens,'
		b'l=kh(),r=Mn(Gce(e)),m=n?.response?.message.model;return!(!n||u(n.response)-u(i)<1e4||!l||l==s||'
		b'r==Mn(Gce(SZ(o)))||m==r||nhn(r)?.has(m))}',
	),
	(
		"model-switch cache-miss dialog: /model caller",
		"grep -ao '[A-Za-z0-9_$]*([a-z],[a-z].mainLoopModel,[a-z].mainLoopModelForSession,[a-z].cacheMissAckedAtOutputTokens,[A-Za-z0-9_$]*([a-z]()))'",
		b'rcr(o,u.mainLoopModel,u.mainLoopModelForSession,u.cacheMissAckedAtOutputTokens,N_r(h()))',
		b'rcr(o,u,h().find((x)=>x.type=="assistant"),u.cacheMissAckedAtOutputTokens,N_r(h()))',
	),
	(
		"model-switch cache-miss dialog: footer picker caller",
		"grep -ao '[A-Za-z0-9_$]*([a-z],[a-z].mainLoopModel,[a-z].mainLoopModelForSession,[a-z].cacheMissAckedAtOutputTokens,[A-Za-z0-9_$]*([a-z]()))'",
		b'rcr(r,u.mainLoopModel,u.mainLoopModelForSession,u.cacheMissAckedAtOutputTokens,N_r(f()))',
		b'rcr(r,u,f().find((x)=>x.type=="assistant"),u.cacheMissAckedAtOutputTokens,N_r(f()))',
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
