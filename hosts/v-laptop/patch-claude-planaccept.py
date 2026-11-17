#!/usr/bin/env python3
"""Plan-accept dialog: add "clear context and implement as Sonnet/Opus" next to the clear-context approval.

1. Option builder. When the clear-context option is shown, two clear-context options follow
   it that also switch the model (Sonnet, Opus), then a single keep-context approval in the session's mode;
   the default-mode keep-context approval survives only where no clear-context option exists
   (remote sessions, setting off). The bypass keep-context row gets a plain label instead of
   upstream's bolded "switch to Bypass Permissions" one.

2. Accept handler. The new values are remapped to the first (clear-context) option before any
   other branch reads it, after a session-only model switch through the same function `/model`
   uses. The ultraplan analytics call pays for the bytes.

Same-length overwrite (padded with spaces) so Bun's compiled-ELF trailer offsets stay valid;
takes effect only through detach-claude-bytecode.py. Anchors are verbatim from claude-code
2.1.326; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-planaccept.py (in your nix config)"

PATCHES = [
	(
		"plan-accept options",
		"grep -ao 'if(![A-Za-z0-9_$]*){if([A-Za-z0-9_$]*){let [A-Za-z0-9_$]*=[A-Za-z0-9_$]*(\"bypassPermissions\".\\{0,1100\\}'",
		(b'if(!De){if(Et){let Ft=a4e("bypassPermissions",{isBypassPermissionsModeAvailable:ee});if(Ft!==null)et["yes-acce'
		  b'pt-edits-keep-context"]=Ft,it["yes-accept-edits-keep-context"]="bypassPermissions",Je.push({label:Ft.node,valu'
		  b'e:"yes-accept-edits-keep-context"})}else if(Rt){let Ft=N_t("exit-plan-resume");et["yes-resume-auto-mode"]=Ft,i'
		  b't["yes-resume-auto-mode"]="auto",Je.push({label:Ft.node,value:"yes-resume-auto-mode"})}else{let Ft=a4e("accept'
		  b'Edits",{labelVariant:"plan-keep-context"});if(Ft!==null)et["yes-accept-edits-keep-context"]=Ft,it["yes-accept-'
		  b'edits-keep-context"]="acceptEdits",Je.push({label:Ft.node,value:"yes-accept-edits-keep-context"})}let Lt=St?nu'
		  b'll:a4e("default",{labelVariant:"plan-keep-context"});if(Lt!==null)et["yes-default-keep-context"]=Lt,it["yes-de'
		  b'fault-keep-context"]="default",Je.push({label:Lt.node,value:"yes-default-keep-context"})}'),
		(b'if(!De&&h)Je.push(...["Sonnet","Opus"].map(m=>({label:`Yes, clear context${mt} and implement as ${m}`,value:"y'
		  b'es-"+m.toLowerCase()})));if(!De){let a="yes-accept-edits-keep-context",d="yes-default-keep-context";if(Et){let'
		  b' Ft=a4e("bypassPermissions",{isBypassPermissionsModeAvailable:ee});if(Ft!==null)et[a]=Ft,it[a]="bypassPermissi'
		  b'ons",Je.push({label:"Yes, implement without clearing context",value:a})}else if(Rt){let Ft=N_t("exit-plan-resu'
		  b'me");et["yes-resume-auto-mode"]=Ft,it["yes-resume-auto-mode"]="auto",Je.push({label:Ft.node,value:"yes-resume-'
		  b'auto-mode"})}else{let Ft=a4e("acceptEdits",{labelVariant:"plan-keep-context"});if(Ft!==null)et[a]=Ft,it[a]="ac'
		  b'ceptEdits",Je.push({label:Ft.node,value:a})}if(!h){let Lt=St?null:a4e("default",{labelVariant:"plan-keep-conte'
		  b'xt"});if(Lt!==null)et[d]=Lt,it[d]="default",Je.push({label:Lt.node,value:d})}}'),
	),
	(
		"plan-accept handler",
		"grep -ao 'async function [A-Za-z0-9_$]*([A-Za-z0-9_$]*){if([A-Za-z0-9_$]*()||[A-Za-z0-9_$]*()){[A-Za-z0-9_$]*();return}.\\{0,400\\}'",
		(b'async function gs(Fs){if(Xr()||Cr()){fs();return}if(!N())return;let Ys=mt.trim(),Ri=Ys||void 0,ji=(Ja)=>iAt(Fs'
		  b',{currentPlan:To,planEditedLocally:cn,acceptFeedback:Ri,trimmedFeedback:Ys,hasImages:yo,imageBlocks:Ja,showCle'
		  b'arContext:Wt,keepContextRow:Oo.keepContextRows[Fs]??null});if(Fs==="ultraplan"&&lo){l("tengu_plan_exit",{planL'
		  b'engthChars:To.length,outcome:b("ultraplan")}),x(ji()),GMo({arg:"",source:"exit_plan_mode",seedPlan:To,getAppSt'
		  b'ate:xe.getState,setAppState:xe.setState,signal:new AbortController().signal,queue:qe,surface:{...lo,note:Ar,qu'
		  b'eue:qe,session:Je},onStatusMessage:Lr,storageV5:De,credentials:Le}).then(Lr).catch(i);return}let bi=Fs==="yes-'
		  b'accept-edits-keep-context"||Fs==="yes-default-keep-context"||Fs==="yes-resume-auto-mode";'),
		(b'async function gs(Fs){if(Xr()||Cr()){fs();return}if(!N())return;{let m=/^yes-(sonnet|opus)$/.exec(Fs)?.[1];if('
		  b'm)Fs=jo[0].value,uwt(Je,m,xe.getState,ee,!1,"command").catch(i)}let Ys=mt.trim(),Ri=Ys||void 0,ji=(Ja)=>iAt(Fs'
		  b',{currentPlan:To,planEditedLocally:cn,acceptFeedback:Ri,trimmedFeedback:Ys,hasImages:yo,imageBlocks:Ja,showCle'
		  b'arContext:Wt,keepContextRow:Oo.keepContextRows[Fs]??null});if(Fs==="ultraplan"&&lo){x(ji()),GMo({arg:"",source'
		  b':"exit_plan_mode",seedPlan:To,getAppState:xe.getState,setAppState:xe.setState,signal:new AbortController().sig'
		  b'nal,queue:qe,surface:{...lo,note:Ar,queue:qe,session:Je},onStatusMessage:Lr,storageV5:De,credentials:Le}).then'
		  b'(Lr).catch(i);return}let bi=Fs.endsWith("-keep-context")||Fs==="yes-resume-auto-mode";'),  # only the two keep-context option values end so
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
