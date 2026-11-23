#!/usr/bin/env bash
# $1: -1 (left) | 1 (right). Cycles tabs of a tabbed container that is the workspace itself or its direct child; no-op elsewhere.
# A workspace with no top-level tabs at all gets its content wrapped into one tab, and a new terminal tab opens on the $1 side.
tree=$(swaymsg -t get_tree)
ws=$(jq 'first(.. | objects | select(.type == "workspace" and any(..; .focused? == true)))' <<<"$tree")
# tiling-only: a focused floating window yields no depth, so no wrap
depth=$(jq 'def depth: if (.nodes | length) == 0 then 0 else .focus[0] as $f | (.nodes[] | select(.id == $f) | depth) + 1 end;
	select(.layout != "tabbed" and (.nodes | length) > 0 and all(.nodes[]; .layout != "tabbed")) | depth' <<<"$ws")
if [ -n "$depth" ]; then
	# split on a focused workspace wraps all its children into one container
	swaymsg "$(printf 'focus parent; %.0s' $(seq "$depth"))split v; layout tabbed" >/dev/null
	[ "$1" = 1 ] && exec swaymsg exec alacritty # new view on a focused workspace appends as last tab
	wrapped=$(swaymsg -t get_tree | jq 'first(.. | objects | select(.layout? == "tabbed" and any(..; .focused? == true))) | .nodes[0].id')
	coproc S { swaymsg -m -t subscribe '["window"]'; }
	swaymsg exec alacritty >/dev/null
	new=$(jq -n 'first(inputs | select(.change == "new") | .container.id)' <&"${S[0]}")
	kill "$S_PID"
	exec swaymsg "[con_id=$new] swap container with con_id $wrapped" # move left would enter the wrapped split
fi
jq --argjson d "$1" '
	def has_focus: any(..; .focused? == true);
	def leaf: if (.nodes | length) == 0 then .id else .focus[0] as $f | .nodes[] | select(.id == $f) | leaf end;
	if .layout == "tabbed" then . else .nodes[] | select(.layout == "tabbed" and has_focus) end
	| (.nodes | map(has_focus) | index(true)) as $i
	| ($i + $d) as $j | select($j >= 0 and $j < (.nodes | length))
	| .nodes[$j] | leaf
' <<<"$ws" | xargs -r -I{} swaymsg "[con_id={}] focus"
