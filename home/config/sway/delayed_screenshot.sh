#!/usr/bin/env bash
# usage: delayed_screenshot.sh <full|region> <seconds>
# Nothing grabs input during the countdown, so hovers/menus stay open; slurp (if any) runs before it.
set -euo pipefail

mode="$1"
secs="$2"
path=~/tmp/Screenshots/scrn-$(date +"%Y-%m-%d-%H-%M-%S").png

case "$mode" in
full) ;;
region) geom="$(slurp)" ;;
*) echo "unknown mode: $mode" >&2; exit 1 ;;
esac

for ((i = secs; i > 0; i--)); do
	eww update screenshot_timer="$i"
	sleep 1
done
eww update screenshot_timer=""
sleep 0.15 # let eww redraw without the counter

case "$mode" in
full) grim -o "$(swaymsg -t get_outputs | jq -r '.[] | select(.focused).name')" "$path" ;;
region) grim -g "$geom" "$path" ;;
esac
swappy -f "$path" -o "$path"
