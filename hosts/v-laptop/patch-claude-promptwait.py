#!/usr/bin/env python3
"""REPL wall-clock cap stops counting while a call waits on the user.

Upstream stops a REPL script 10m (async: 2h) after it starts, time at permission prompts
included, so an ExitPlanMode / AskUserQuestion / permission prompt left unanswered for 10m
dies with "Stopped at the 10m limit while the ... call was waiting to run". The one-shot timer
becomes a 1s tick that adds elapsed time to a credit whenever `ol` (upstream's own
"calls waiting to run" list) is non-empty; the cap fires once elapsed minus credit reaches it.
The script's own work keeps the cap.

Same-length overwrite (padded with spaces) so Bun's compiled-ELF trailer offsets stay valid;
takes effect only through detach-claude-bytecode.py. Anchor verbatim from claude-code
2.1.326; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-promptwait.py (in your nix config)"
HINT = "grep -ao '[A-Za-z0-9_$]*=[A-Za-z0-9_$]*([A-Za-z0-9_$]*,()=>{let [A-Za-z0-9_$]*=[A-Za-z0-9_$]*(.\\{0,450\\}wall_clock_limit.\\{0,80\\}'"
ANCHOR = (b'De=Dn(ia,()=>{let mt=ol(we,K,Le,Date.now(),ee),ht="call";try{ht=wc([...we.values()].filter((ze)=>ze.phase==="e'
		  b'xecuting").map((ze)=>ze.toolName),p)}catch(ze){i(ze)}let fe=mt.map((ze)=>({toolName:ze.toolName,ranBefore:at.g'
		  b'et(ze.toolUseId)==="sandboxRetry",...at.get(ze.toolUseId)==="pluginHook"&&{rerunByHook:!0}}));ce("wall_clock_l'
		  b'imit",Pt(Error(bc(Pe,fe,ht)),oi(Pe,fe,ht)))},Pe)')
REPLACEMENT = (b'De=((s,l,w,c,F)=>(F=()=>{let n=Date.now();if(ol(we,K,Le,n,ee).length)w+=n-l;l=n;if(n-s-w<Pe){c=Dn(ia,F,1e3);re'
		  b'turn}let ht="call";try{ht=wc([...we.values()].filter((ze)=>ze.phase==="executing").map((ze)=>ze.toolName),p)}c'
		  b'atch(ze){i(ze)}ce("wall_clock_limit",Pt(Error(bc(Pe,[],ht)),oi(Pe,[],ht)))},c=Dn(ia,F,1e3),()=>c()))(Date.now('
		  b'),Date.now(),0)')


def die(msg: str) -> None:
	sys.stderr.write(
		"\n"
		"================================================================================\n"
		"  claude-code prompt-wait patch FAILED\n"
		"================================================================================\n"
		f"  {msg}\n"
		"\n"
		"  Upstream has likely changed the minified code or its variable names.\n"
		f"  1. Edit {THIS_FILE}\n"
		f"  2. Locate the new spelling in bin/.claude-unwrapped:\n"
		f"       {HINT} <binary>\n"
		"  3. Update anchor/replacement (same-length overwrite), or drop the patch if upstream\n"
		"     stopped counting permission waits toward the REPL wall clock.\n"
		"================================================================================\n"
	)
	sys.exit(1)


path = sys.argv[1]
with open(path, "rb") as f:
	data = f.read()
original_len = len(data)

if len(REPLACEMENT) > len(ANCHOR):
	die(f"replacement is {len(REPLACEMENT) - len(ANCHOR)} bytes longer than the anchor.")
count = data.count(ANCHOR)
if count != 1:
	die(f"expected 1 occurrence of the anchor in {path}, found {count}.")
data = data.replace(ANCHOR, REPLACEMENT.ljust(len(ANCHOR)))
print("patched prompt-wait wall clock", file=sys.stderr)

assert len(data) == original_len, "overwrite must preserve byte length"
with open(path, "wb") as f:
	f.write(data)
