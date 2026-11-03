#!/usr/bin/env bash
# `/` in choose-tree. Exact session name (`*` favorite prefix optional): cursor onto it, expanded; arriving from another session collapses the rest. Otherwise tags every session containing the query, cursor stays.
# `$1`: client; `$2`: tree-mode pane; query in @tree_search
c=$1 p=$2
q=$(tmux show -gv @tree_search \; set -gu @tree_search)
sessions=$(tmux list-sessions -F '#S')

key() { tmux send-keys -t "$p" "$@"; }
move() { # $1 → $2, both row indices
	if (($2 > $1)); then key -N $(($2 - $1)) Down; elif (($2 < $1)); then key -N $(($1 - $2)) Up; fi
}
# tree-mode exposes nothing to formats, so its `:` (run a command on every tagged row, or on the cursor's if none) is the only readout. Args: tmux command to run first
readback() {
	tmux "$@" \; set -g @tree_rows '' \; send-keys -K -c "$c" :
	tmux send-keys -K -c "$c" -l 'set -ga @tree_rows "%%\n"' # -l skips the client's key queue, so it can't share a call with the queued `:`
	tmux send-keys -K -c "$c" Enter
	local r
	for _ in {1..200}; do
		r=$(tmux show -gv @tree_rows)
		[ -n "$r" ] && break
		sleep 0.002
	done
	[ -n "$r" ] || { tmux display -c "$c" "tree_search: readback timed out"; exit 1; }
	printf '%s' "$r"
}

cur=$(readback send-keys -t "$p" T)
cur_s=${cur#=}
cur_s=${cur_s%%:*}
x=$(printf '%s\n' "$sessions" | grep -xF -e "$q" -e "*$q" | head -1)
if [ -n "$x" ] && [ "$x" != "$cur_s" ]; then
	rank=$(printf '%s\n' "$sessions" | LC_ALL=C sort | grep -nxF -- "$x" | cut -d: -f1) # choose-tree -O name is strcmp
	key M-- g
	move 1 "$rank"
	key Right
	exit 0
fi

# Layout: walking down tagging every row leaves exactly the rows without visible children tagged (tagging a child untags its parents); their ancestors fill in the rest.
# Down wraps, so each pass walks no further than a lower bound on the rows left.
last=$(readback send-keys -t "$p" G)
total_s=$(printf '%s\n' "$sessions" | wc -l) # shortcut: assumes no `f` filter hides sessions; a filtered tree over-walks and garbles the tags
rows=()
pre=(send-keys -t "$p" T g \;)
while :; do
	n_s=0
	for r in "${rows[@]}"; do [[ $r == *: ]] && ((n_s++)); done
	m=$((total_s - n_s))
	((m < 1)) && m=1
	mapfile -t rows < <(readback "${pre[@]}" send-keys -t "$p" -N "$m" t Down | awk '{ s = substr($0, 1, index($0, ":")); w = substr($0, 1, index($0, ".")); if (!(s in seen)) { seen[s]; print s } if (w != "" && !(w in seen)) { seen[w]; print w } if (!($0 in seen)) { seen[$0]; print } }')
	pre=()
	[ "${rows[-1]}" = "$last" ] && break
done
key T # the walk ended wrapped back onto row 0

at=0
for i in "${!rows[@]}"; do [ "${rows[i]}" = "$cur" ] && cur_i=$i; done
if [ -n "$x" ]; then
	for i in "${!rows[@]}"; do [ "${rows[i]}" = "=$x:" ] && x_i=$i; done
	move 0 "$x_i"
	[[ ${rows[x_i + 1]} == "=$x:"?* ]] || key Right
	exit 0
fi
for i in "${!rows[@]}"; do
	r=${rows[i]}
	[[ $r == *: ]] || continue
	r=${r#=}
	[[ ${r%:} == *"$q"* ]] || continue
	move "$at" "$i"
	at=$i
	key t
done
move "$at" "$cur_i"
