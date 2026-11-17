#!/usr/bin/env bash
# PreToolUse(Bash): CC's `find` shim (embedded bfs) ignores .gitignore and crawls target/, node_modules/ etc: 30s+ on ~/s where fd takes 0.06s
cmd=$(jq -r '.tool_input.command // empty')
if grep -qE '(^|[;&|({`]|\$\(|\b(then|do|else|xargs|sudo|time|timeout [0-9a-z.]+))[[:space:]]*find([[:space:]]|$)' <<<"$cmd"; then
  echo "Blocked: use fd (gitignore-aware; -H for hidden, -I for ignored, -e ext, -t f/d, -x cmd, --changed-within 1d). Only if you need a predicate fd lacks, use \`command find\` and prune build dirs." >&2
  exit 2
fi
