#!/usr/bin/env python3
"""PreToolUse(Bash|Monitor|Write|Edit): cargo output in /tmp. It is tmpfs, so a target dir there is RAM and swap, and kache can't reflink into it."""
import json
import os
import re
import sys

REDIRECT = r"(?:\bCARGO_(?:BUILD_)?(?:TARGET|BUILD)_DIR\b[\"']?(?:\s*[=:]\s*|\s+)|--target-dir(?:=|\s+)|\b(?:target|build)-dir\s*=\s*)"
VALUE = r"""(?:"[^"\n]*"|'[^'\n]*'|\\["']|\$\([^)\n]*\)|[^\s;&|()"'`,}])+"""
CARGO = r"""(?:cargo|"?\$(?:CARGO\b|\{CARGO\})"?)"""
FLAGS = r"(?:(?:\+\S+|-{1,2}[A-Za-z][\w-]*(?:=\S+)?)\s+)*"
COMPILES = "b|build|c|check|t|test|r|run|bench|clippy|d|doc|rustc|rustdoc|fix|nextest|lbuild|llvm-cov|miri|expand|semver-checks|insta|mutants|watch|hack|package|publish"
TOKEN = re.compile(rf"""
	(?P<open>\() | (?P<close>\))
	| (?P<redirect>{REDIRECT})(?P<target>{VALUE})
	| (?<![\w./$-])(?:cd|pushd)\s+(?:--\s+)?(?P<cd>{VALUE})
	| (?<![\w./$-])(?P<name>[A-Za-z_]\w*)=(?P<value>{VALUE})
	| (?<![\w.`|-])(?P<build>(?:{CARGO}\s+{FLAGS}(?:-C\s+(?P<dir>{VALUE})\s+{FLAGS})?(?:{COMPILES})|cargo-lbuild\s+lbuild|dx\s+(?:build|bundle|serve|check))(?![\w.=/:-])(?P<args>[^;&|\n]*))
""", re.X)
RUNS = re.compile(r"(?<![\w.-])(?:cargo|dx|nix|just|make|npm|bash|sh|fish|python3?|node)\s|\.sh\b|\$\{?CARGO\b|(?:^|\s)\./")
TEXT_ONLY = re.compile(r"(?:^|[;&|\n(]|\$\()\s*(?:rg|grep|ugrep|pgrep|pkill|which|type|echo|printf|git|gh|sed|awk|jq|fd|cat|du|ls|rm|ssh)\b[^;&|\n)]*$")
SCRIPT = re.compile(r"(?:\.(?:sh|bash|fish|nix|toml|mk|just|py|m?[jt]s)|/(?:justfile|Makefile))$")


def resolve(value, names, cwd):
	value = value.replace('"', "").replace("'", "").replace("\\", "")
	value = re.sub(r"\$\(\s*mktemp[^)]*\)?", "/tmp/mktemp", value)
	value = re.sub(r"\$\{?(\w+)(?::?-[^}]*)?\}?", lambda m: names.get(m[1], m[0]), value)
	if value.startswith("~"):
		value = os.path.expanduser(value)
	return os.path.realpath(os.path.join(cwd, value))


def in_tmp(path):
	return re.match(r"/(?:tmp|var/tmp|dev/shm|run/user)(?:/|$)", path)


def offence(text, cwd):
	names = {"HOME": os.path.expanduser("~"), "TMPDIR": "/tmp", "TMP": "/tmp", "XDG_RUNTIME_DIR": "/run/user", "PWD": cwd}
	redirected, stack, runs = None, [], RUNS.search(text)
	for m in TOKEN.finditer(text):
		if m["open"]:
			stack.append((cwd, redirected))
		elif m["close"]:
			if stack:
				cwd, redirected = stack.pop()
		elif m["redirect"]:
			redirected = resolve(m["target"], names, cwd)
			if in_tmp(redirected) and runs and not TEXT_ONLY.search(text[:m.start()]):
				return redirected
		elif m["cd"]:
			cwd = names["PWD"] = resolve(m["cd"], names, cwd)
		elif m["name"]:
			names[m["name"]] = resolve(m["value"], names, cwd) if re.match(r"[\"']*[/~$.]", m["value"]) else m["value"]
		elif not TEXT_ONLY.search(text[:m.start()]) and "-Zscript" not in m["build"]:  # a script's target/ is under ~/.cargo
			flag = re.search(rf"--target-dir(?:=|\s+)({VALUE})", m["args"])
			manifest = re.search(rf"--manifest-path(?:=|\s+)({VALUE})", m["args"])
			if flag:
				out = resolve(flag[1], names, cwd)
			elif redirected:
				out = redirected
			elif manifest:
				out = os.path.join(os.path.dirname(resolve(manifest[1], names, cwd)), "target")
			else:
				out = os.path.join(resolve(m["dir"], names, cwd) if m["dir"] else cwd, "target")
			if in_tmp(out):
				return out
	return None


def main():
	call = json.load(sys.stdin)
	args, cwd = call["tool_input"], call["cwd"]
	if call["tool_name"] in ("Write", "Edit"):
		text = args.get("content") or args.get("new_string") or ""
		if not SCRIPT.search(args["file_path"]) or os.path.realpath(args["file_path"]) == os.path.realpath(__file__):
			return
		bad = next((m["target"] for m in TOKEN.finditer(text) if m["redirect"] and in_tmp(resolve(m["target"], {"TMPDIR": "/tmp"}, "/"))), None)
	else:
		bad = offence(args.get("command") or "", cwd)
	if not bad:
		return
	print(f"""BLOCKED: this puts cargo's output in {bad}.

Compiling into /tmp is an atrocious idea. Never try it again, in any spelling: CARGO_TARGET_DIR, --target-dir, a config file, a script that sets it, or a clone in /tmp built where it lies.

  - /tmp is RAM. A target dir is gigabytes of it. They helped fill this machine's swap, which slows every other agent and the user's desktop.
  - It is the slow way. The existing target/ has the incremental state; an empty one compiles every workspace crate and test binary from zero.
  - It throws the cache away. kache reflinks dependencies into a target/ under ~/s without copying; into /tmp it copies every one, into RAM.

Compile normally: drop the redirect, run plain `cargo b` / `cargo t` in the checkout, and let it reuse the target/ that is already there.

  - "Blocking waiting for file lock"? Wait. The build you wait for is warming the same target/ for you.
  - Another agent is editing this checkout, or you need another revision? `git worktree add .claude/worktrees/<name> <rev>` in that repo: its own target/, its own lock, dependencies from kache.
  - Need one crate rebuilt clean? `cargo clean -p <crate>`.
  - Probing how something behaves? A bin in the repo's examples/.
  - Not our repo, or the probe needs a crate of its own? Under ~/s/tmp/.

Do not answer this with a redirect to some other directory. The target/ you need exists: use it.""", file=sys.stderr)
	sys.exit(2)


main()
