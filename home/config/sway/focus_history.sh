#!/usr/bin/env bash
# Vim-style jumplists over focused windows, one global and one per workspace. `daemon` records focus changes; `back`/`forward` walk them (Ctrl+o/Ctrl+i).
set -euo pipefail

dir=/tmp/sway_focus_history # <list>.ids: con ids, oldest first; <list>.pos: index of the current entry
max=16
tree='recurse(.nodes[], .floating_nodes[])'
mkdir -p "$dir"
exec 9>"$dir/lock"

push() { # <list> <id>
	local ids p i kept=()
	[ -f "$dir/$1.ids" ] || { : >"$dir/$1.ids"; echo -1 >"$dir/$1.pos"; }
	mapfile -t ids <"$dir/$1.ids"
	p=$(<"$dir/$1.pos")
	[ "$p" -lt 0 ] || [ "${ids[$p]}" != "$2" ] || return 0 # equal means the focus came from this list's own back/forward
	for i in "${ids[@]:0:p+1}"; do [ "$i" = "$2" ] || kept+=("$i"); done
	kept+=("$2")
	[ "${#kept[@]}" -le $max ] || kept=("${kept[@]: -max}")
	printf '%s\n' "${kept[@]}" >"$dir/$1.ids"
	echo $((${#kept[@]} - 1)) >"$dir/$1.pos"
}

mru() { # <list> <id>; unlike the jumplist, jumps never truncate it
	local ids i kept=("$2")
	[ -f "$dir/$1.mru" ] || : >"$dir/$1.mru"
	mapfile -t ids <"$dir/$1.mru"
	for i in "${ids[@]}"; do [ "$i" = "$2" ] || kept+=("$i"); done
	printf '%s\n' "${kept[@]:0:max}" >"$dir/$1.mru"
}

case "$1" in
daemon)
	for p in $(pgrep -xf "bash $0 daemon"); do [ "$p" = $$ ] || kill "$p"; done # exec_always re-runs on reload
	rm -f "$dir"/*.ids "$dir"/*.pos "$dir"/*.mru
	swaymsg -t subscribe -m '["window"]' | jq --unbuffered -r 'select(.change == "focus" and .container.scratchpad_state == "none") | .container.id' | while read -r id; do
		ws=$(swaymsg -t get_tree | jq --argjson id "$id" "first($tree | select(.type == \"workspace\" and any($tree; .id == \$id))) | .id")
		flock 9
		push global "$id"
		[ -z "$ws" ] || { push "ws_$ws" "$id"; mru "ws_$ws" "$id"; } # empty when the window closed before we looked
		flock -u 9
	done
	;;
back | forward | flip)
	ws_scope="first($tree | select(.type == \"workspace\" and any($tree; .focused)))"
	case "$*" in
	"back global" | "forward global") scope='.' name='"global"' ;;
	"back workspace" | "forward workspace" | flip) scope=$ws_scope name='"ws_\(.id)"' ;;
	*) echo "usage: $0 back|forward global|workspace | flip" >&2 && exit 1 ;;
	esac
	out=$(swaymsg -t get_tree | jq -r "$scope | $name + \" \" + ([$tree | select(.pid != null and .scratchpad_state == \"none\" and (.focused | not)) | .id] | join(\" \"))")
	read -r list live <<<"$out"
	live=" $live " # con ids are never reused, so closed, scratchpadded or (for workspace lists) moved-away windows are just skipped
	flock 9
	[ -f "$dir/$list.ids" ] || exit 0 # nothing focused here since the daemon started
	if [ "$1" = flip ]; then
		mapfile -t ids <"$dir/$list.mru"
		for i in "${!ids[@]}"; do [[ $live == *" ${ids[$i]} "* ]] && break; done
		[[ $live == *" ${ids[$i]} "* ]] || exit 0
	else
		[ "$1" = back ] && step=-1 || step=1
		mapfile -t ids <"$dir/$list.ids"
		p=$(<"$dir/$list.pos")
		i=$((p + step))
		while [ "$i" -ge 0 ] && [ "$i" -lt "${#ids[@]}" ] && [[ $live != *" ${ids[$i]} "* ]]; do i=$((i + step)); done
		[ "$i" -ge 0 ] && [ "$i" -lt "${#ids[@]}" ] || exit 0
		echo "$i" >"$dir/$list.pos"
	fi
	flock -u 9
	swaymsg "[con_id=${ids[$i]}] focus" >/dev/null
	;;
*)
	echo "usage: $0 daemon | back|forward global|workspace | flip" >&2
	exit 1
	;;
esac
