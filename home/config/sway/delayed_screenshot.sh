#!/usr/bin/env bash
# usage: delayed_screenshot.sh <seconds>
# Nothing grabs input during the countdown, so hovers/menus stay open; slurp runs before it.
set -euo pipefail

secs="$1"
path=~/tmp/Screenshots/scrn-$(date +"%Y-%m-%d-%H-%M-%S").png
geom="$(slurp)"

for ((i = secs; i > 0; i--)); do
	eww update screenshot_timer="$i"
	sleep 1
done
eww update screenshot_timer=""
sleep 0.15 # let eww redraw without the counter

grim -g "$geom" "$path"
swappy -f "$path" -o "$path"
