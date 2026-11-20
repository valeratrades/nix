#!/usr/bin/env python3
"""Code Mode, once opted into, stays on: no account, policy, provider, model or feature-flag check can refuse it or restart claude without it.

Those checks read state that is transiently missing (logged out, policy unread, flag fetch late under restore_sessions'
contended start); each miss restarts without Code Mode, and a Code Mode session then refuses to resume. Kept: the
opt-in itself, the caveats consent, and the structural checks (runtime, bash, entrypoint, unattended, engine, mods).

Same-length overwrites so Bun's compiled-ELF trailer offsets stay valid; take effect only through
detach-claude-bytecode.py. Anchors are verbatim from claude-code 2.1.326; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-codemodegate.py (in your nix config)"
HINT = "grep -ao '.\\{0,3000\\}export{zWi,TFn,fdl,pdl,mdl,hdl,U_o,gdl,_dl}' <binary>   # the module exporting closeCodeModeOptInAfterSetup"


def blank(code):
	return b" " * len(code)


ACCOUNT_CHECKS_AT_START = b'if(!h())return"provider";if(Y())return"credentials";if(R())return"compliance";if(S())return"otel";let t=e.cliModel===void 0?at():e.cliModel==="default"?jt(Zpe()??Pd()):jt(e.cliModel);return TFn(t)?void 0:"model"}'
FLAG_AT_START = b'let O=A();if(O===void 0)return t("no_flags");if(o.lastCheck=e.lastCheck,!O||!L()){if(a)return t(O?"unsaved":"gate");return yIa()}'
FLAG_AT_START_KEPT = b'if(o.lastCheck=e.lastCheck,!L()){if(a)return t("unsaved");return yIa()}'
SETUP_REVIEW = b',!Xwe()&&jg()!==void 0)return"credentials";if(!b()||!v())return"admin_unread";if(m())return"admin";if(R())return"compliance";if(S())return"otel";if(!h())return"provider";if(!TFn(at()))return"model";if(A()===void 0)return"no_flags";if(!W())return"gate";'
AFTER_SETUP = b'n=!o.reviewed?"no_setup":!b()||!v()||e==="unread"?"admin_unread":e==="changed"?"credential_changed":m()?"admin":R()?"compliance":S()?"otel":!h()||X()?"provider":!TFn(at())?"model":void 0;'

PATCHES = [
	(ACCOUNT_CHECKS_AT_START, blank(ACCOUNT_CHECKS_AT_START[:-1]) + b"}"),
	(FLAG_AT_START, FLAG_AT_START_KEPT + b" " * (len(FLAG_AT_START) - len(FLAG_AT_START_KEPT))),
	(SETUP_REVIEW, b")" + blank(SETUP_REVIEW[2:]) + b";"), # closes the `if(await Promise.all(...)` the anchor starts inside, as an empty statement
	(AFTER_SETUP, b"n=void 0" + b" " * (len(AFTER_SETUP) - len(b"n=void 0;")) + b";"),
]

path = sys.argv[1]
with open(path, "rb") as f:
	data = f.read()
original_len = len(data)

for anchor, replacement in PATCHES:
	assert len(anchor) == len(replacement), anchor
	count = data.count(anchor)
	if count != 1:
		sys.stderr.write(
			"\n"
			"================================================================================\n"
			"  claude-code code-mode-gate patch FAILED\n"
			"================================================================================\n"
			f"  expected 1 occurrence of the anchor in {path}, found {count}:\n"
			f"    {anchor.decode()}\n"
			"\n"
			"  Upstream has likely changed the minified code or its variable names.\n"
			f"  1. Edit {THIS_FILE}\n"
			f"  2. Locate the new spelling:\n"
			f"       {HINT}\n"
			"  3. Update the anchor (same-length overwrite), or drop it if that check is gone.\n"
			"================================================================================\n"
		)
		sys.exit(1)
	data = data.replace(anchor, replacement)
print("patched code mode gate", file=sys.stderr)

assert len(data) == original_len, "overwrite must preserve byte length"
with open(path, "wb") as f:
	f.write(data)
