#!/bin/sh
# `/` in favtree. Exact session name (`*` favorite prefix optional): cursor on it, expanded. Otherwise: tags every session containing the query, cursor stays. `$1`: choose-tree target under the cursor; `$2`: pane to reopen choose-tree in
q=$(tmux show -gv @tree_search)
tmux set -gu @tree_search
cur=${1#=}
cur=${cur%%:*}
sessions=$(tmux list-sessions -F '#S' | LC_ALL=C sort) # choose-tree -O name is strcmp
tmux run-shell -t "$2" -C favtree # fresh tree: everything collapsed, so a session's row is its rank
tmux send-keys -t "$2" g
exact=$(printf '%s\n' "$sessions" | grep -nxF -e "$q" -e "*$q" | head -1 | cut -d: -f1)
if [ -n "$exact" ]; then
	if [ "$exact" -gt 1 ]; then tmux send-keys -t "$2" -N $((exact - 1)) Down; fi
	tmux send-keys -t "$2" Right
	exit 0
fi
at=1
for r in $(printf '%s\n' "$sessions" | grep -nF -- "$q" | cut -d: -f1); do
	if [ "$r" -gt "$at" ]; then tmux send-keys -t "$2" -N $((r - at)) Down; fi
	at=$r
	tmux send-keys -t "$2" t
done
r=$(printf '%s\n' "$sessions" | grep -nxF -- "$cur" | cut -d: -f1)
tmux send-keys -t "$2" g
if [ "$r" -gt 1 ]; then tmux send-keys -t "$2" -N $((r - 1)) Down; fi
