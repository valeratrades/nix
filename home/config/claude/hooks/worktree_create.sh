#!/usr/bin/env bash
# WorktreeCreate: claude's own layout (.claude/worktrees/<name>, branch worktree-<name>), through `git wt` where the repo has it
set -euo pipefail
in="$(cat)"
name="$(jq -er .name <<<"$in")"
cd "$(jq -er .cwd <<<"$in")"
root="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
dir="$root/.claude/worktrees/$name"
if git config --get alias.wt >/dev/null; then wt=(wt); else wt=(worktree add); fi
git "${wt[@]}" "$dir" -b "worktree-$name" HEAD >&2 # HEAD, not origin's: work here lands on local main unpushed
echo "$dir"
