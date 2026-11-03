#!/usr/bin/env bash
# Vim-style jumplist over focused windows. `daemon` records focus changes; `back`/`forward` walk them (Ctrl+o/Ctrl+i).
set -euo pipefail

dir=/tmp/sway_focus_history
list=$dir/list # con ids, oldest first
pos=$dir/pos   # index into list of the current entry
max=16
mkdir -p "$dir"
exec 9>"$dir/lock"

case "$1" in
daemon)
	for p in $(pgrep -xf "bash $0 daemon"); do [ "$p" = $$ ] || kill "$p"; done # exec_always re-runs on reload
	: >"$list"
	echo -1 >"$pos"
	swaymsg -t subscribe -m '["window"]' | jq --unbuffered -r 'select(.change == "focus" and .container.scratchpad_state == "none") | .container.id' | while read -r id; do
		flock 9
		mapfile -t ids <"$list"
		p=$(<"$pos")
		if [ "$p" -lt 0 ] || [ "${ids[$p]}" != "$id" ]; then # equal means the focus came from our own back/forward
			kept=()
			for i in "${ids[@]:0:p+1}"; do [ "$i" = "$id" ] || kept+=("$i"); done
			kept+=("$id")
			[ "${#kept[@]}" -le $max ] || kept=("${kept[@]: -max}")
			printf '%s\n' "${kept[@]}" >"$list"
			echo $((${#kept[@]} - 1)) >"$pos"
		fi
		flock -u 9
	done
	;;
back | forward)
	[ "$1" = back ] && step=-1 || step=1
	flock 9
	mapfile -t ids <"$list"
	p=$(<"$pos")
	live=" $(swaymsg -t get_tree | jq -r '[recurse(.nodes[], .floating_nodes[]) | select(.pid != null and .scratchpad_state == "none") | .id] | join(" ")') "
	i=$((p + step))
	while [ "$i" -ge 0 ] && [ "$i" -lt "${#ids[@]}" ] && [[ $live != *" ${ids[$i]} "* ]]; do i=$((i + step)); done # con ids are never reused, so closed or scratchpadded windows are just skipped
	[ "$i" -ge 0 ] && [ "$i" -lt "${#ids[@]}" ] || exit 0
	echo "$i" >"$pos"
	flock -u 9
	swaymsg "[con_id=${ids[$i]}] focus" >/dev/null
	;;
*)
	echo "usage: $0 daemon|back|forward" >&2
	exit 1
	;;
esac
