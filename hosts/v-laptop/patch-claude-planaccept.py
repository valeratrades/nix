#!/usr/bin/env python3
"""Plan-accept dialog: add "clear context and implement as Sonnet" next to the clear-context approval.

1. Option builder. When the clear-context option is shown, a second clear-context option follows
   it that also switches the model. The keep-context approvals are dropped from that dialog;
   they survive only where no clear-context option exists (remote sessions, setting off), so
   every dialog keeps an approval.

2. Accept handler. The new value is remapped to the first (clear-context) option before any
   other branch reads it, after a session-only model switch through the same function `/model`
   uses. The ultraplan analytics call pays for the bytes.

Same-length overwrite (padded with spaces) so Bun's compiled-ELF trailer offsets stay valid;
takes effect only through detach-claude-bytecode.py. Anchors are verbatim from claude-code
2.1.303; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-planaccept.py (in your nix config)"

PATCHES = [
	(
		"plan-accept options",
		"grep -ao 'if(![A-Za-z0-9_$]*){if([A-Za-z0-9_$]*){let [A-Za-z0-9_$]*=[A-Za-z0-9_$]*(\"bypassPermissions\".\\{0,1100\\}'",
		b'if(!ve){if(ee){let it=yAe("bypassPermissions",{isBypassPermissionsModeAvailable:ee});'
		b'if(it!==null)Oe["yes-accept-edits-keep-context"]=it,Ue["yes-accept-edits-keep-context"]="bypassPermissions",'
		b'De.push({label:it.node,value:"yes-accept-edits-keep-context"})}'
		b'else if(Ge){let it=M_n("exit-plan-resume");Oe["yes-resume-auto-mode"]=it,Ue["yes-resume-auto-mode"]="auto",'
		b'De.push({label:it.node,value:"yes-resume-auto-mode"})}'
		b'else{let it=yAe("acceptEdits",{labelVariant:"plan-keep-context"});'
		b'if(it!==null)Oe["yes-accept-edits-keep-context"]=it,Ue["yes-accept-edits-keep-context"]="acceptEdits",'
		b'De.push({label:it.node,value:"yes-accept-edits-keep-context"})}'
		b'let tt=yAe("default",{labelVariant:"plan-keep-context"});'
		b'if(tt!==null)Oe["yes-default-keep-context"]=tt,Ue["yes-default-keep-context"]="default",'
		b'De.push({label:tt.node,value:"yes-default-keep-context"})}',
		b'if(!ve&&h)De.push({label:`Yes, clear context${ze} and implement as Sonnet`,value:"yes-sonnet"});'
		b'if(!ve&&!h){let a="yes-accept-edits-keep-context",d="yes-default-keep-context";'
		b'if(ee){let it=yAe("bypassPermissions",{isBypassPermissionsModeAvailable:ee});'
		b'if(it!==null)Oe[a]=it,Ue[a]="bypassPermissions",De.push({label:it.node,value:a})}'
		b'else if(Ge){let it=M_n("exit-plan-resume");Oe["yes-resume-auto-mode"]=it,Ue["yes-resume-auto-mode"]="auto",'
		b'De.push({label:it.node,value:"yes-resume-auto-mode"})}'
		b'else{let it=yAe("acceptEdits",{labelVariant:"plan-keep-context"});'
		b'if(it!==null)Oe[a]=it,Ue[a]="acceptEdits",De.push({label:it.node,value:a})}'
		b'let tt=yAe("default",{labelVariant:"plan-keep-context"});'
		b'if(tt!==null)Oe[d]=tt,Ue[d]="default",De.push({label:tt.node,value:d})}',
	),
	(
		"plan-accept handler",
		"grep -ao 'async function [A-Za-z0-9_$]*([A-Za-z0-9_$]*){if([A-Za-z0-9_$]*()||[A-Za-z0-9_$]*()){[A-Za-z0-9_$]*();return}.\\{0,400\\}'",
		b'async function er(fr){if(Or()||or()){ns();return}if(!L())return;'
		b'let dr=ze.trim(),tr=dr||void 0,Nr=(Ps)=>Mit(fr,{currentPlan:Ro,planEditedLocally:fn,acceptFeedback:tr,'
		b'trimmedFeedback:dr,hasImages:uo,imageBlocks:Ps,showClearContext:_t,keepContextRow:po.keepContextRows[fr]??null});'
		b'if(fr==="ultraplan"&&Dt){i("tengu_plan_exit",{planLengthChars:Ro.length,outcome:b("ultraplan")}),C(Nr()),'
		b'B_r({arg:"",source:"exit_plan_mode",seedPlan:Ro,getAppState:le.getState,setAppState:le.setState,'
		b'signal:new AbortController().signal,queue:De,surface:{...Dt,note:rr,queue:De,session:Oe},'
		b'onStatusMessage:Pr,storageV5:ve,credentials:_e}).then(Pr).catch(l);return}'
		b'let gr=fr==="yes-accept-edits-keep-context"||fr==="yes-default-keep-context"||fr==="yes-resume-auto-mode";',
		b'async function er(fr){if(Or()||or()){ns();return}if(!L())return;'
		b'if(fr==="yes-sonnet")fr=jo[0].value,Mqe(Oe,"sonnet",le.getState,ee,!1,"command").catch(l);'
		b'let dr=ze.trim(),tr=dr||void 0,Nr=(Ps)=>Mit(fr,{currentPlan:Ro,planEditedLocally:fn,acceptFeedback:tr,'
		b'trimmedFeedback:dr,hasImages:uo,imageBlocks:Ps,showClearContext:_t,keepContextRow:po.keepContextRows[fr]??null});'
		b'if(fr==="ultraplan"&&Dt){C(Nr()),'
		b'B_r({arg:"",source:"exit_plan_mode",seedPlan:Ro,getAppState:le.getState,setAppState:le.setState,'
		b'signal:new AbortController().signal,queue:De,surface:{...Dt,note:rr,queue:De,session:Oe},'
		b'onStatusMessage:Pr,storageV5:ve,credentials:_e}).then(Pr).catch(l);return}'
		b'let gr=fr.endsWith("-keep-context")||fr==="yes-resume-auto-mode";',  # only the two keep-context option values end so
	),
]


def die(name: str, hint: str, msg: str) -> None:
	sys.stderr.write(
		"\n"
		"================================================================================\n"
		f"  claude-code plan-accept patch FAILED: {name}\n"
		"================================================================================\n"
		f"  {msg}\n"
		"\n"
		"  Upstream has likely changed the minified code or its variable names.\n"
		f"  1. Edit {THIS_FILE}\n"
		f"  2. Locate the new spelling in bin/.claude-unwrapped:\n"
		f"       {hint} <binary>\n"
		"  3. Update the anchor/replacement (same-length overwrite; trim the replacement if\n"
		"     it outgrew the anchor), or drop the patch if upstream added a model choice.\n"
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
