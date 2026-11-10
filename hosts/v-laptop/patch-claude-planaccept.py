#!/usr/bin/env python3
"""Plan-accept dialog: add "clear context and implement as Sonnet" next to the clear-context approval.

1. Option builder. When the clear-context option is shown, a second clear-context option follows
   it that also switches the model, then a single keep-context approval in the session's mode;
   the default-mode keep-context approval survives only where no clear-context option exists
   (remote sessions, setting off). The bypass keep-context row gets a plain label instead of
   upstream's bolded "switch to Bypass Permissions" one.

2. Accept handler. The new value is remapped to the first (clear-context) option before any
   other branch reads it, after a session-only model switch through the same function `/model`
   uses. The ultraplan analytics call pays for the bytes.

Same-length overwrite (padded with spaces) so Bun's compiled-ELF trailer offsets stay valid;
takes effect only through detach-claude-bytecode.py. Anchors are verbatim from claude-code
2.1.322; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-planaccept.py (in your nix config)"

PATCHES = [
	(
		"plan-accept options",
		"grep -ao 'if(![A-Za-z0-9_$]*){if([A-Za-z0-9_$]*){let [A-Za-z0-9_$]*=[A-Za-z0-9_$]*(\"bypassPermissions\".\\{0,1100\\}'",
		b'if(!Oe){if(Pt){let Mt=HBe("bypassPermissions",{isBypassPermissionsModeAvailable:te});'
		b'if(Mt!==null)Je["yes-accept-edits-keep-context"]=Mt,et["yes-accept-edits-keep-context"]="bypassPermissions",'
		b'Ve.push({label:Mt.node,value:"yes-accept-edits-keep-context"})}'
		b'else if(wt){let Mt=$st("exit-plan-resume");Je["yes-resume-auto-mode"]=Mt,et["yes-resume-auto-mode"]="auto",'
		b'Ve.push({label:Mt.node,value:"yes-resume-auto-mode"})}'
		b'else{let Mt=HBe("acceptEdits",{labelVariant:"plan-keep-context"});'
		b'if(Mt!==null)Je["yes-accept-edits-keep-context"]=Mt,et["yes-accept-edits-keep-context"]="acceptEdits",'
		b'Ve.push({label:Mt.node,value:"yes-accept-edits-keep-context"})}'
		b'let Ot=xt?null:HBe("default",{labelVariant:"plan-keep-context"});'
		b'if(Ot!==null)Je["yes-default-keep-context"]=Ot,et["yes-default-keep-context"]="default",'
		b'Ve.push({label:Ot.node,value:"yes-default-keep-context"})}',
		b'if(!Oe&&h)Ve.push({label:`Yes, clear context${rt} and implement as Sonnet`,value:"yes-sonnet"});'
		b'if(!Oe){let a="yes-accept-edits-keep-context",d="yes-default-keep-context";'
		b'if(Pt){let Mt=HBe("bypassPermissions",{isBypassPermissionsModeAvailable:te});'
		b'if(Mt!==null)Je[a]=Mt,et[a]="bypassPermissions",Ve.push({label:"Yes, implement without clearing context",value:a})}'
		b'else if(wt){let Mt=$st("exit-plan-resume");Je["yes-resume-auto-mode"]=Mt,et["yes-resume-auto-mode"]="auto",'
		b'Ve.push({label:Mt.node,value:"yes-resume-auto-mode"})}'
		b'else{let Mt=HBe("acceptEdits",{labelVariant:"plan-keep-context"});'
		b'if(Mt!==null)Je[a]=Mt,et[a]="acceptEdits",Ve.push({label:Mt.node,value:a})}'
		b'if(!h){let Ot=xt?null:HBe("default",{labelVariant:"plan-keep-context"});'
		b'if(Ot!==null)Je[d]=Ot,et[d]="default",Ve.push({label:Ot.node,value:d})}}',
	),
	(
		"plan-accept handler",
		"grep -ao 'async function [A-Za-z0-9_$]*([A-Za-z0-9_$]*){if([A-Za-z0-9_$]*()||[A-Za-z0-9_$]*()){[A-Za-z0-9_$]*();return}.\\{0,400\\}'",
		b'async function Dr(zn){if(lr()||mr()){Mr();return}if(!D())return;'
		b'let fs=rt.trim(),_s=fs||void 0,Js=(ra)=>OSt(zn,{currentPlan:xo,planEditedLocally:On,acceptFeedback:_s,'
		b'trimmedFeedback:fs,hasImages:Cr,imageBlocks:ra,showClearContext:Dt,keepContextRow:Yo.keepContextRows[zn]??null});'
		b'if(zn==="ultraplan"&&to){l("tengu_plan_exit",{planLengthChars:xo.length,outcome:b("ultraplan")}),M(Js()),'
		b'rao({arg:"",source:"exit_plan_mode",seedPlan:xo,getAppState:xe.getState,setAppState:xe.setState,'
		b'signal:new AbortController().signal,queue:We,surface:{...to,note:us,queue:We,session:Ve},'
		b'onStatusMessage:kr,storageV5:Oe,credentials:Fe}).then(kr).catch(a);return}'
		b'let yi=zn==="yes-accept-edits-keep-context"||zn==="yes-default-keep-context"||zn==="yes-resume-auto-mode";',
		b'async function Dr(zn){if(lr()||mr()){Mr();return}if(!D())return;'
		b'if(zn==="yes-sonnet")zn=cn[0].value,edt(Ve,"sonnet",xe.getState,te,!1,"command").catch(a);'
		b'let fs=rt.trim(),_s=fs||void 0,Js=(ra)=>OSt(zn,{currentPlan:xo,planEditedLocally:On,acceptFeedback:_s,'
		b'trimmedFeedback:fs,hasImages:Cr,imageBlocks:ra,showClearContext:Dt,keepContextRow:Yo.keepContextRows[zn]??null});'
		b'if(zn==="ultraplan"&&to){M(Js()),'
		b'rao({arg:"",source:"exit_plan_mode",seedPlan:xo,getAppState:xe.getState,setAppState:xe.setState,'
		b'signal:new AbortController().signal,queue:We,surface:{...to,note:us,queue:We,session:Ve},'
		b'onStatusMessage:kr,storageV5:Oe,credentials:Fe}).then(kr).catch(a);return}'
		b'let yi=zn.endsWith("-keep-context")||zn==="yes-resume-auto-mode";',  # only the two keep-context option values end so
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
