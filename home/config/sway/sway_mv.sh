#!/usr/bin/env bash
# usage: sway_mv.sh <workspace> | sway_mv.sh --dir <-1|1>
# Moves the focused top-level tab, else everything on the workspace, into the target's top-level tabs; target content without them gets wrapped into one tab first. Focus follows.
# --dir swaps with the neighbouring top-level tab, else crosses to workspace number +-1, landing on the near edge.
set -euo pipefail
defs='
	def tiling_focus: [.focus[] as $f | .nodes[] | select(.id == $f)][0];
	def top: if .layout == "tabbed" then . else tiling_focus | select(.layout == "tabbed") end;
	def depth: if (.nodes | length) == 0 then 0 else (tiling_focus | depth) + 1 end;
	def tleaf: if (.nodes | length) == 0 then .id else tiling_focus | tleaf end;
	def ws($n): first(.. | objects | select(.type == "workspace" and .name == $n));
'
# split on a focused workspace wraps all its children into one container
wrap() { printf '[con_id=%s] focus; %ssplit v' "$(jq "$defs tleaf" <<<"$1")" "$(printf 'focus parent; %.0s' $(seq "$(jq "$defs depth" <<<"$1")"))"; }

src=$(swaymsg -t get_tree | jq 'first(.. | objects | select(.type == "workspace" and any(..; .focused? == true)))')
leaf=$(jq 'first(.. | objects | select(.focused? == true and .type == "con")) | .id' <<<"$src")
[ -n "$leaf" ] || exit 0 # empty workspace or floating focus
tab=$(jq "$defs"' top | tiling_focus | .id' <<<"$src")

if [ "$1" = --dir ]; then
	d=$2
	nb=$(jq --argjson d "$d" "$defs"' top | tiling_focus.id as $c | [.nodes[].id] | (index($c) + $d) as $j | select($j >= 0) | .[$j] // empty' <<<"$src")
	[ -n "$nb" ] && exec swaymsg "[con_id=$tab] swap container with con_id $nb; [con_id=$leaf] focus" >/dev/null
	target=$(( $(jq .num <<<"$src") + d ))
	(( target >= 0 && target <= 9 )) || exit 0
	[ "$d" = 1 ] && land=0 || land=-1
else
	target=$1
	land=-1
	[ "$target" = "$(jq -r .name <<<"$src")" ] && exit 0
fi

[ -z "$tab" ] && [ "$(jq '.nodes | length' <<<"$src")" = 1 ] && tab=$(jq '.nodes[0].id' <<<"$src")
if [ -z "$tab" ]; then
	swaymsg "$(wrap "$src")" >/dev/null
	tab=$(swaymsg -t get_tree | jq --arg n "$(jq -r .name <<<"$src")" "$defs"' ws($n) | .nodes[0].id')
fi

dst=$(swaymsg -t get_tree | jq --arg n "$target" "$defs"' ws($n) // empty')
if [ -n "$dst" ] && [ "$(jq '.nodes | length' <<<"$dst")" -gt 0 ] && [ -z "$(jq "$defs top | .id" <<<"$dst")" ]; then
	swaymsg "$(wrap "$dst"); layout tabbed" >/dev/null
	dst=$(swaymsg -t get_tree | jq --arg n "$target" "$defs"' ws($n)')
fi
y=
[ -n "$dst" ] && y=$(jq "$defs"' top | select(.type != "workspace") | .id' <<<"$dst")
if [ -n "$y" ]; then
	swaymsg "[con_id=$y] mark --add _sway_mv; [con_id=$tab] move container to mark _sway_mv; unmark _sway_mv" >/dev/null
else
	swaymsg "[con_id=$tab] move container to workspace $target" >/dev/null
fi

swaps=$(swaymsg -t get_tree | jq -r --argjson c "$tab" --argjson k "$land" '
	first(.. | objects | select(any(.nodes[]?; .id == $c))) | [.nodes[].id] as $ids | ($ids | index($c)) as $p
	| (if $k < 0 then ($ids | length) - 1 else $k end) as $k
	| if $k < $p then [range($p - 1; $k - 1; -1)] else [range($p + 1; $k + 1)] end
	| map("[con_id=\($c)] swap container with con_id \($ids[.]); ") | add // ""')
swaymsg "$swaps[con_id=$leaf] focus" >/dev/null
