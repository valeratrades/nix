#!/usr/bin/env python3
"""Account switching: "Switch to account N" entries in the rate-limit menu (`/rate-limit-options`), `/rotate` showing
that menu with only those entries, and every running claude following ~/.claude/accounts/current in place.

The logic lives in claude-accounts.mjs, as no chunk has room for it. This script writes the .mjs with the
minified internals it needs resolved to their chunk + export name, and splices its hooks into two modules:
1. the credential-dir module (loaded at start-up): its license header starts the .mjs's watcher;
2. the menu module: its license header becomes `$acc()`, importing the .mjs; the options list gains the .mjs's
   entries, appended so a late arrival never shifts the focused row; the select handler routes `acct:<name>`
   values to the .mjs's switchTo, showing a status dialog meanwhile, as the panel host retires a menu left
   without one and drops its result. A context flagged `rotate` drops the stock rows;
3. the command-list module: its license header defines `/rotate`, calling the menu with that flag (a new export would
   stay invisible: bun reads exports from the precomputed module_info), and the list gains it.

Same-length overwrites (each license header absorbs the growth); take effect only through
detach-claude-bytecode.py. Anchors are verbatim from claude-code 2.1.303; minified names churn
every release.

Usage: patch-claude-accounts.py <binary> <claude-accounts.mjs template> <output .mjs path>
Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import re
import struct
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-accounts.py (in your nix config)"
TRAILER = b"\n---- Bun! ----\n"
RECORD = 52
NAME = rb"[\w$]+"

MENU_SPLICES = [
	(
		"options",
		b'let ue=_,Pn=R(!1),Rn,En;',
		b'let[$ao,$as]=y([]),ue=t.rotate?$ao:[..._,...$ao],Pn=R(!1),Rn,En;',
	),
	(
		"options load",
		b'Pn.current=!0,i("tengu_rate_limit_options_menu_shown",{...Wbn(o),entry:T8(t.submittedFromComposer)?b("typed"):b("not_typed"),rows:ue.map(ir),blocked:eM(o)})}',
		b'Pn.current=!0,$acc().then(m=>m.options()).then($as,e=>$as([{label:`Account switch unavailable: ${e}`,value:"acct:",disabled:!0}]))}',
	),
	(
		"dispatch",
		b'ht=function Gt(F){',
		b'ht=function Gt(F){if(F.startsWith("acct:"))return fe(e(be,{title:"What do you want to do?",onCancel:nr,exitOnCtrlCD:!0,color:"suggestion",hideInputGuide:!0,children:e(n,{dimColor:!0,children:`Switching to account ${F.slice(5)}\\u2026`})})),$acc().then(m=>m.switchTo(F.slice(5),t,l)).catch(e=>l(`Account switch failed: ${e?.stack??e}`));',
	),
]
COMMAND_LIST = (b'Z6e,e3e,Fen,', b'Z6e,e3e,$rot,Fen,')

# each pattern matches exactly once across all modules; its groups name the minified internals
INTERNALS = [
	rb"function (?P<mle>" + NAME + rb")\(\{retryCount:\w=0,force:\w=!1,entryAccessToken:",
	rb"function (?P<Nn>" + NAME + rb")\(\)\{if\(" + NAME + rb"\(\)\)return null;let (\w)=" + NAME + rb"\.of\(" + NAME + rb"\(\)\.host\);if\(\2\.value!==void 0\)return \2\.value;",
	rb"async function (?P<uVe>" + NAME + rb")\(\w,\{storageV5:\w,credentials:\w\}=\{\}\)\{let \w=await " + NAME + rb"\(\w,\{storageV5:\w,credentials:\w\}\),\w=await " + NAME + rb"\(\w,\w\);if\((?P<DI>" + NAME + rb")\(\),process\.env\.CLAUDE_CODE_OAUTH_TOKEN\)",
	rb"async function (?P<kAe>" + NAME + rb")\(\w,\w,\w\)\{if\(\w\.onChangeAPIKey\(\),!\w\)return\{bridgeDisconnected:!1,",
	rb"function (?P<wn>" + NAME + rb")\(\)\{return " + NAME + rb"\(\)\?" + NAME + rb"\(\)\.oauthAccount:void 0\}",
	rb"function (?P<Br>" + NAME + rb")\(\)\{return " + NAME + rb"\(\)\.host\.credentialSlots\.gatewayAuth\(\)\}",	rb"clientId:\w\}=\w,\w=(?P<Kn>" + NAME + rb")\(\),\w=" + NAME + rb"\(\);try\{let \w=" + NAME + rb"\.of\(" + NAME + rb"\(\)\.host\),\w=await \w\.mutate\(",
]
# credential-storage dir; bundled into several modules, the hook goes into the one mle's module imports
CREDENTIAL_DIR = rb"function (?P<jx>" + NAME + rb")\(\)\{let \w=process\.env\.CLAUDE_SECURESTORAGE_CONFIG_DIR;"


def die(msg: str) -> None:
	sys.stderr.write(
		"\n"
		"================================================================================\n"
		"  claude-code account-switch patch FAILED\n"
		"================================================================================\n"
		f"  {msg}\n"
		"\n"
		"  Upstream has likely changed the minified code or its variable names.\n"
		f"  1. Edit {THIS_FILE}\n"
		"  2. Dump the module sources (see detach-claude-bytecode.py for the graph layout) and\n"
		"     re-derive the anchor from the rate-limit menu (tengu_rate_limit_options_menu_shown)\n"
		"     or the internal's body.\n"
		"================================================================================\n"
	)
	sys.exit(1)


def modules(data: bytes) -> dict[str, slice]:
	e_shoff, = struct.unpack_from("<Q", data, 0x28)
	e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x3A)
	strtab_off = struct.unpack_from("<IIQQQQIIQQ", data, e_shoff + e_shstrndx * e_shentsize)[4]
	for i in range(e_shnum):
		sh = struct.unpack_from("<IIQQQQIIQQ", data, e_shoff + i * e_shentsize)
		if data[strtab_off + sh[0]:data.index(b"\0", strtab_off + sh[0])] == b".bun":
			base, size = sh[4] + 8, sh[5]
			break
	else:
		die("no .bun section in the ELF")
	trailer = base + size - 8 - len(TRAILER)
	if data[trailer:trailer + len(TRAILER)] != TRAILER:
		die("bun trailer not at the end of the .bun payload")
	table_off, table_len = struct.unpack_from("<II", data, trailer - 24)
	out = {}
	for i in range(table_len // RECORD):
		rec = base + table_off + i * RECORD
		(name_off, name_len), (src_off, src_len) = struct.unpack_from("<II", data, rec), struct.unpack_from("<II", data, rec + 8)
		out[data[base + name_off:base + name_off + name_len].decode()] = slice(base + src_off, base + src_off + src_len)
	return out


def export_of(mod: str, local: str) -> tuple[str, str]:
	"""Where `local` (a name bound in `mod`) can be imported from, and under what name."""
	src = sources[mod].decode("utf-8", "replace")
	for clause in re.findall(r"export\{([^}]*)\}", src):
		for item in clause.split(","):
			parts = item.split(" as ")
			if parts[0] == local:
				return mod, parts[-1]
	for clause, origin in re.findall(r'import\{([^}]*)\}from"([^"]+)"', src):
		for item in clause.split(","):
			parts = item.split(" as ")
			if parts[-1] == local:
				return origin, parts[0]
	die(f"{local} is neither exported from nor imported into {mod}")


def hits(pattern: bytes) -> list[tuple[str, re.Match]]:
	return [(mod, m) for mod, src in sources.items() for m in re.finditer(pattern, src)]


def with_header(mod: str, src: bytes, code: bytes) -> bytes:
	"""`src` (`mod`'s source after its other splices) with its license header replaced by `code`, padded to the original length."""
	header = re.match(rb"// @bun @bytecode\n(// [^\n]*\n|\n)*?(?=// Version:)", src)
	if header is None or b"Anthropic PBC" not in header.group(0):
		die(f"license header of {mod} not where expected")
	code = b"// @bun @bytecode\n" + code
	slack = len(sources[mod]) - (len(src) - header.end() + len(code) + 1)
	if slack < 0:
		die(f"{mod}: splices outgrow the license header by {-slack} bytes")
	print(f"patched {mod} ({slack} bytes of header left)", file=sys.stderr)
	return code + b" " * slack + b"\n" + src[header.end():]


binary, template, out_mjs = sys.argv[1:4]
with open(binary, "rb") as f:
	data = bytearray(f.read())
original_len = len(data)
graph = modules(data)
sources = {name: bytes(data[s]) for name, s in graph.items()}
load = b'import("' + out_mjs.encode() + b'")'

menus = [name for name, src in sources.items() if b"tengu_rate_limit_options_menu_shown" in src]
if len(menus) != 1:
	die(f"expected the rate-limit menu in 1 module, found {menus}")
menu = menus[0]
src = sources[menu]
for name, anchor, replacement in MENU_SPLICES:
	if src.count(anchor) != 1:
		die(f"{name}: expected 1 occurrence of the anchor in {menu}, found {src.count(anchor)}")
	src = src.replace(anchor, replacement)
data[graph[menu]] = with_header(menu, src, b"function $acc(){return " + load + b"}")

lists = [name for name, src in sources.items() if b'{type:"local-jsx",name:"rate-limit-options",' in src]
if len(lists) != 1:
	die(f"expected the rate-limit-options command in 1 module, found {lists}")
anchor, replacement = COMMAND_LIST
if sources[lists[0]].count(anchor) != 1:
	die(f"command list: expected 1 occurrence of the anchor in {lists[0]}, found {sources[lists[0]].count(anchor)}")
data[graph[lists[0]]] = with_header(lists[0], sources[lists[0]].replace(anchor, replacement), (
	b'var $rot={type:"local-jsx",name:"rotate",description:"Switch every claude to another account",requires:{ink:!0},'
	b'load:()=>import("' + menu.encode() + b'").then(m=>({call:(d,c)=>m.call(d,{...c,rotate:!0})}))};'
))

resolved: dict[str, tuple[str, str]] = {}
for pattern in INTERNALS:
	found = hits(pattern)
	if len(found) != 1:
		die(f"expected 1 match of {pattern!r}, found {len(found)} in {[mod for mod, _ in found]}")
	mod, m = found[0]
	for internal, local in m.groupdict().items():
		resolved[internal] = export_of(mod, local.decode())
chunks = sorted({mod for mod, _ in resolved.values()})
loader = (
	f"const [{', '.join(f'm{i}' for i in range(len(chunks)))}] = await Promise.all([{', '.join(f'import({mod!r})' for mod in chunks)}]);\n"
	f"\treturn {{ {', '.join(f'{internal}: m{chunks.index(mod)}.{exported}' for internal, (mod, exported) in resolved.items())} }};"
)

mle_mod = next(mod for mod, _ in hits(INTERNALS[0]))
dirs = [(mod, export_of(mod, m.group("jx").decode())) for mod, m in hits(CREDENTIAL_DIR)]
imported = [mod for mod, (origin, exported) in dirs if re.search(r'import\{[^}]*(?<![\w$])' + re.escape(exported) + r'(?![\w$])[^}]*\}from"' + re.escape(origin) + '"', sources[mle_mod].decode("utf-8", "replace"))]
if len(imported) != 1:
	die(f"expected {mle_mod} to import the credential dir from 1 of {[mod for mod, _ in dirs]}, found {imported}")
data[graph[imported[0]]] = with_header(imported[0], sources[imported[0]], load + b".then(m=>m.watch())")

with open(template) as f:
	mjs = f.read()
if mjs.count("/* INTERNALS */") != 1:
	die(f"{template} lacks its `/* INTERNALS */` line")
with open(out_mjs, "w") as f:
	f.write(mjs.replace("/* INTERNALS */", loader))

assert len(data) == original_len, "overwrite must preserve byte length"
with open(binary, "wb") as f:
	f.write(data)
