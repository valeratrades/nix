#!/bin/sh
# very dumb script to choose the monitor for rofi

monitors_count=$(swaymsg -t get_outputs | jq length)

base=$(swaymsg -t get_tree | jq '.nodes | map([recurse(.nodes[]?, .floating_nodes[]?) | .focused] | any) | index(true)')

if [ "$monitors_count" -eq 1 ]; then
	printf $(expr $base - 1)
else
	printf $base
fi
