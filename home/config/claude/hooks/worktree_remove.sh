#!/usr/bin/env bash
# WorktreeRemove: what claude does for worktrees it makes itself — the branch goes with the directory
set -euo pipefail
dir="$(jq -er .worktree_path)"
branch="$(git -C "$dir" branch --show-current)"
cd "$(dirname "$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)")"
git worktree remove --force "$dir"
[ -z "$branch" ] || git branch -D "$branch" >&2
