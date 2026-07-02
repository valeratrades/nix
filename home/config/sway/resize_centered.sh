#!/usr/bin/env dash
# Resize the focused window to WxH while keeping its center fixed.
# `_` for either dimension keeps its current value.
#
# Two complications, both handled below:
#  - The position must be recomputed from the size the window ACTUALLY took,
#    not the requested one: clients (e.g. Chrome) enforce a min size and snap
#    to it, so requested != actual.
#  - That snap is asynchronous — it lands a frame or two after `resize set`
#    returns. Reading the size immediately gives the pre-snap value, so we
#    poll until it stops changing before repositioning. Without this the
#    window's left edge stays put while the client grows rightward, and the
#    center creeps across the screen when toggling presets.

[ "$#" -eq 2 ] || { printf "usage: resize_centered <width> <height>\n" >&2; exit 2; }
w="$1"; h="$2"

focused='.. | objects | select(.focused==true) | "\(.rect.x) \(.rect.y) \(.rect.width) \(.rect.height)"'

set -- $(swaymsg -t get_tree | jq -r "$focused")
[ "$#" -eq 4 ] || { printf "error: no focused window\n" >&2; exit 1; }
cx=$(( $1 + $3 / 2 ))
cy=$(( $2 + $4 / 2 ))
[ "$w" = _ ] && w=$3
[ "$h" = _ ] && h=$4

swaymsg "resize set ${w}px ${h}px" >/dev/null

prev=""
i=0
while [ "$i" -lt 30 ]; do
	set -- $(swaymsg -t get_tree | jq -r "$focused")
	cur="$3 $4"
	[ "$cur" = "$prev" ] && break
	prev="$cur"
	sleep 0.02
	i=$(( i + 1 ))
done

swaymsg "move absolute position $(( cx - $3 / 2 ))px $(( cy - $4 / 2 ))px" >/dev/null
