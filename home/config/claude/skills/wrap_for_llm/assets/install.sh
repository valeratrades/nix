#!/usr/bin/env sh
# Symlinks this directory in as the `<name>` skill, for one agent.
#
#   ./install.sh claude            → ~/.claude/skills/
#   ./install.sh codex             → ${CODEX_HOME:-~/.codex}/skills/
#   ./install.sh claude <project>  → <project>/.claude/skills/
#   ./install.sh codex  <project>  → <project>/.agents/skills/
set -eu

src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
name=<name>
tool=${1:-}
proj=${2:-}

if [ -n "$proj" ]; then
	proj=$(CDPATH= cd -- "$proj" && pwd)
	claude_dir="$proj/.claude/skills"
	codex_dir="$proj/.agents/skills"
else
	claude_dir="$HOME/.claude/skills"
	codex_dir="${CODEX_HOME:-$HOME/.codex}/skills"
fi

case $tool in
claude) d=$claude_dir ;;
codex) d=$codex_dir ;;
*)
	echo "usage: $0 <claude|codex> [project]" >&2
	exit 2
	;;
esac

link="$d/$name"
if [ -e "$link" ] && [ ! -L "$link" ]; then
	echo "$link exists and is not a symlink — refusing to touch it" >&2
	exit 1
fi
mkdir -p "$d"
rm -f "$link"
ln -s "$src" "$link"
echo "$link -> $src"
