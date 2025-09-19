#!/bin/sh
pgrep -f "/bin/sh .*$(basename "$0")" | grep -v $$ | xargs kill 2>/dev/null # kill other instances of this script

while true; do
	switched_to_monitor=$(swaymsg -t subscribe '["workspace"]' | jq --unbuffered -r 'select(.change == "focus") | .current.output')
	if [ "$switched_to_monitor" = "" ]; then # happens when the new focused workspace is empty
		continue
	fi
	swaymsg input type:tablet_tool map_to_output "$switched_to_monitor"
done
