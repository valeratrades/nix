#!/usr/bin/env sh
# Symlinks this directory in as the `<name>` skill.
#
#   ./install.sh              → ~/.claude/skills/  and  ${CODEX_HOME:-~/.codex}/skills/
#   ./install.sh <project>    → <project>/.claude/skills/  and  <project>/.agents/skills/
set -eu

src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
name=<name>

if [ $# -gt 0 ]; then
	proj=$(CDPATH= cd -- "$1" && pwd)
	dirs="$proj/.claude/skills $proj/.agents/skills"
else
	dirs="$HOME/.claude/skills ${CODEX_HOME:-$HOME/.codex}/skills"
fi

for d in $dirs; do
	link="$d/$name"
	if [ -e "$link" ] && [ ! -L "$link" ]; then
		echo "$link exists and is not a symlink — refusing to touch it" >&2
		exit 1
	fi
	mkdir -p "$d"
	rm -f "$link"
	ln -s "$src" "$link"
	echo "$link -> $src"
done
