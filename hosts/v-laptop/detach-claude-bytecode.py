#!/usr/bin/env python3
"""Make source patches to claude-code's bun-compiled ELF take effect.

Since 2.1.280 every bundled module ships precompiled JSC bytecode next to its source, and bun
runs the bytecode without checking it against the source. An edit to the source alone is dead.
Zeroing a module's bytecode length in the standalone module graph makes bun compile that
module from its (patched) source instead.

Usage: detach-claude-bytecode.py <original> <patched>
Detaches exactly the modules whose source differs between the two files, so every patch
applied before this step takes effect without listing modules by hash-churning chunk name.

Module graph layout (bun standalone, `.bun` ELF section = u64 payload size + payload):
payload ends with Offsets{u64 byte_count, StringPointer modules, u32 entry, StringPointer argv,
u32 flags} + "\\n---- Bun! ----\\n"; `modules` is an array of 52-byte records: six
StringPointer{u32 offset, u32 length} (name, contents, sourcemap, bytecode, module_info,
bytecode_origin_path) + 4 flag bytes. Offsets are relative to the payload start.
"""
import struct
import sys

TRAILER = b"\n---- Bun! ----\n"
RECORD = 52


def die(msg: str) -> None:
	sys.stderr.write(
		"\n"
		"================================================================================\n"
		"  claude-code bytecode detach FAILED\n"
		"================================================================================\n"
		f"  {msg}\n"
		"\n"
		"  Without this step the source patches in hosts/v-laptop/ are dead code: bun runs\n"
		"  each module's embedded bytecode. Upstream bun likely changed the standalone\n"
		"  module-graph layout; re-derive it from bun's src/StandaloneModuleGraph.zig.\n"
		"================================================================================\n"
	)
	sys.exit(1)


def bun_section(data: bytes) -> tuple[int, int]:
	e_shoff, = struct.unpack_from("<Q", data, 0x28)
	e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x3A)
	strtab_off = struct.unpack_from("<IIQQQQIIQQ", data, e_shoff + e_shstrndx * e_shentsize)[4]
	for i in range(e_shnum):
		sh = struct.unpack_from("<IIQQQQIIQQ", data, e_shoff + i * e_shentsize)
		name = data[strtab_off + sh[0]:data.index(b"\0", strtab_off + sh[0])]
		if name == b".bun":
			return sh[4], sh[5]
	die("no .bun section in the ELF")


original_path, patched_path = sys.argv[1], sys.argv[2]
with open(original_path, "rb") as f:
	original = f.read()
with open(patched_path, "rb") as f:
	patched = bytearray(f.read())
if len(original) != len(patched):
	die("patched binary changed length; every patch must be a same-length overwrite")

sec_off, sec_size = bun_section(patched)
base = sec_off + 8
if struct.unpack_from("<Q", patched, sec_off)[0] != sec_size - 8:
	die(".bun section does not start with its payload size")
trailer = base + sec_size - 8 - len(TRAILER)
if patched[trailer:trailer + len(TRAILER)] != TRAILER:
	die("bun trailer not at the end of the .bun payload")
modules_off, modules_len = struct.unpack_from("<II", patched, trailer - 24)
if modules_len % RECORD:
	die(f"module table length {modules_len} is not a multiple of {RECORD}")

detached = []
for i in range(modules_len // RECORD):
	rec = base + modules_off + i * RECORD
	(name_off, name_len), (src_off, src_len) = struct.unpack_from("<II", patched, rec), struct.unpack_from("<II", patched, rec + 8)
	name = bytes(patched[base + name_off:base + name_off + name_len])
	if not name.startswith(b"/$bunfs/root/"):
		die(f"module record {i} does not name a /$bunfs path: {name[:40]!r}")
	src = slice(base + src_off, base + src_off + src_len)
	if original[src] == patched[src]:
		continue
	struct.pack_into("<I", patched, rec + 28, 0)
	detached.append(name.decode())

if not detached:
	die("no module source differs; nothing was patched before this step")
with open(patched_path, "wb") as f:
	f.write(patched)
print(f"detached bytecode of {len(detached)} patched module(s): {', '.join(detached)}", file=sys.stderr)
