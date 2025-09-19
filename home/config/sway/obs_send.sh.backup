#!/bin/sh

to_send=${1}

focused_pid=$(swaymsg -t get_tree | jq '.. | select(.type? == "con" and .focused == true) | .pid')
obs_pid=$(swaymsg -t get_tree | jq '.. | select(.app_id? == "com.obsproject.Studio") | .pid' | head -n 1)

swaymsg [pid="$obs_pid"] focus

wtype "${to_send}"

swaymsg [pid="$focused_pid"] focus
