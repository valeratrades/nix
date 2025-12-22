#!/usr/bin/env bash
# Show scratchpad if it has windows, otherwise create a new terminal and move it there

scratchpad_count=$(swaymsg -t get_tree | jq '[recurse(.nodes[], .floating_nodes[]) | select(.scratchpad_state) | select(.scratchpad_state | test("fresh|changed"))] | length')

if [ "$scratchpad_count" -eq 0 ]; then
    swaymsg exec alacritty
    swaymsg -t subscribe '["window"]' | jq -c --unbuffered 'select(.change == "focus")' | head -n1 > /dev/null
    sleep 0.05 # if we don't wait here, will be deformed (pertain the proportions of the initial layout)
    swaymsg move scratchpad
    swaymsg scratchpad show
else
    swaymsg scratchpad show
fi
