#!/usr/bin/env python3
"""Rewind (`/rewind`, double Esc) forks into a new session instead of dropping the old branch.

Stock: restoring the conversation to an earlier message keeps the same session id; the next message is written with the
rewound parent, splitting the transcript tree inside one jsonl, and `claude -r` later restores only the newest leaf, so
the route that was rewound away from is gone. Here, after the in-memory rewind, the kept messages are branched into a
new session through the stock `/branch` function and resumed, then the rewound prompt is put back in the input. The
original session file is never written to by the rewound route, so it stays resumable at its old leaf.

The helper lives in the module's license header (same-length overwrite); its growth at the call site is paid for by two
analytics calls on the rewind path. Takes effect only through detach-claude-bytecode.py. Anchors are verbatim from
claude-code 2.1.326; minified names churn every release.

Invoked from: hosts/v-laptop/patched-claude-code.nix (overrideAttrs.postFixup).
"""
import re
import struct
import sys

THIS_FILE = "hosts/v-laptop/patch-claude-autobranch.py (in your nix config)"
TRAILER = b"\n---- Bun! ----\n"
RECORD = 52
NAME = rb"[\w$]+"

CALL_SITE = (
	rb"restoreMessageSync=\((?P<h>\w+),(?P<x>\w+),(?P<N>\w+)=\[\]\)=>\{let (?P<L>\w+)=(?P=N)\[0\];if\((?P=L)===void 0\)\{"
	rb"if\(this\.rewindConversationTo\((?P=h),(?P=x)\),(?P<keep>!\(this\.#\w+&&(?P=x)===\"auto_restore_cancel\"\))\)"
	rb"this\.restoreDraftFrom\((?P=h)\);return\}"
)
# the append helper's own spelling gives the minified `warning message` builder
WARNING = rb'messages:\[(?P<It>' + NAME + rb')\("That message is no longer in the active context'
BRANCH_FN = rb"async function (?P<fn>" + NAME + rb")\(\w,\w,\w=\{\}\)\{let \w=\w\(\),\w=" + NAME + rb"\(\w\),"
# analytics calls on the rewind path, dropped to pay for the helper
PAYERS = [
	rb'l\("tengu_conversation_rewind",\{preRewindMessageCount:[^}]*\}\),',
	rb';l\("tengu_refusal_fallback_rewind_unwind",\{.*?source:f\(x\)\}\)',
	rb';p\("repl_rewind_conversation",\{source:f\(x\)\}\)',
]


def die(msg: str) -> None:
	sys.stderr.write(
		"\n"
		"================================================================================\n"
		"  claude-code rewind auto-branch patch FAILED\n"
		"================================================================================\n"
		f"  {msg}\n"
		"\n"
		"  Upstream has likely changed the minified code or its variable names.\n"
		f"  1. Edit {THIS_FILE}\n"
		"  2. Dump the module sources (see detach-claude-bytecode.py for the graph layout) and\n"
		"     re-derive the anchors from `restoreMessageSync=` (rewind restore) and the function\n"
		"     holding \"tengu_conversation_forked\" (/branch).\n"
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


def only(pattern: bytes, src: bytes, what: str, mod: str) -> re.Match:
	found = list(re.finditer(pattern, src, re.S))
	if len(found) != 1:
		die(f"{what}: expected 1 match in {mod}, found {len(found)}")
	return found[0]


binary = sys.argv[1]
with open(binary, "rb") as f:
	data = bytearray(f.read())
original_len = len(data)
graph = modules(data)
sources = {name: bytes(data[s]) for name, s in graph.items()}

targets = [name for name, src in sources.items() if b"restoreMessageSync=(" in src and b"rewindConversationTo(" in src]
if len(targets) != 1:
	die(f"expected the rewind controller in 1 module, found {targets}")
target = targets[0]
src = sources[target]

forks = [name for name, s in sources.items() if b'"tengu_conversation_forked"' in s]
if len(forks) != 1:
	die(f"expected /branch in 1 module, found {forks}")
fork_mod = forks[0]
fork_src = sources[fork_mod]
branch_fn = only(BRANCH_FN, fork_src, "/branch function", fork_mod).group("fn")
assert fork_src.index(b"tengu_conversation_forked") > fork_src.index(b"async function " + branch_fn + b"("), "forked event sits in the branch function"
exported = None
for clause in re.findall(rb"export\{([^}]*)\}", fork_src):
	for item in clause.split(b","):
		parts = item.split(b" as ")
		if parts[0] == branch_fn:
			exported = parts[-1]
if exported is None:
	die(f"{branch_fn!r} is not exported from {fork_mod}")

site = only(CALL_SITE, src, "rewind restore", target)
warning = only(WARNING, src, "warning builder", target).group("It")
h, x, N, L, keep = (site.group(k) for k in ("h", "x", "N", "L", "keep"))
patched = (
	b"restoreMessageSync=(" + h + b"," + x + b"," + N + b"=[])=>{let " + L + b"=" + N + b"[0];if(" + L + b"===void 0){"
	b"if(this.rewindConversationTo(" + h + b"," + x + b")," + x + b'==="message_selector")return $fork(this).then(()=>this.restoreDraftFrom(' + h + b"));"
	b"if(" + keep + b")this.restoreDraftFrom(" + h + b");return}"
)
src = src[:site.start()] + patched + src[site.end():]

for pattern in PAYERS:
	src, n = re.subn(pattern, b"", src, flags=re.S)
	if n != 1:
		die(f"analytics payer {pattern!r}: expected 1 match in {target}, found {n}")

helper = (
	b"// @bun @bytecode\n"
	b"function $fork(c){let n=s=>c.transcript.apply({type:\"append\",messages:[" + warning + b"(s,\"warning\")]});"
	b"return import(\"" + fork_mod.encode() + b"\").then(m=>m." + exported + b"({messages:c.transcript.getSnapshot(),storageV5:c.storageV5,resume:c.resume},n,{}))"
	b".catch(e=>n(`Rewind fork failed: ${e}`))}"
)
header = re.match(rb"// @bun @bytecode\n(// [^\n]*\n|\n)*", src)
if header is None or b"Anthropic PBC" not in header.group(0):
	die(f"license header of {target} not where expected")
slack = len(sources[target]) - (len(src) - header.end() + len(helper) + 1)
if slack < 0:
	die(f"{target}: the helper and call site outgrow the freed bytes by {-slack}")
data[graph[target]] = helper + b" " * slack + b"\n" + src[header.end():]
print(f"patched {target} ({slack} bytes spare)", file=sys.stderr)

assert len(data) == original_len, "overwrite must preserve byte length"
with open(binary, "wb") as f:
	f.write(data)
