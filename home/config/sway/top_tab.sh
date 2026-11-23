#!/usr/bin/env bash
# $1: -1 (left) | 1 (right). Cycles tabs of a tabbed container that is the workspace itself or its direct child; no-op elsewhere.
swaymsg -t get_tree | jq --argjson d "$1" '
	def has_focus: any(..; .focused? == true);
	def leaf: if (.nodes | length) == 0 then .id else .focus[0] as $f | .nodes[] | select(.id == $f) | leaf end;
	.. | objects | select(.type == "workspace" and has_focus)
	| if .layout == "tabbed" then . else .nodes[] | select(.layout == "tabbed" and has_focus) end
	| (.nodes | map(has_focus) | index(true)) as $i
	| ($i + $d) as $j | select($j >= 0 and $j < (.nodes | length))
	| .nodes[$j] | leaf
' | xargs -r -I{} swaymsg "[con_id={}] focus"
