#!/bin/sh

file_path="${HOME}/.config/sway/pin_focused/pid.txt"

if [ -f "$file_path" ]; then
	focused_workspace=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused==true).name')
	pinned_pid=$(cat ${HOME}/.config/sway/pin_focused/pid.txt)
	swaymsg "for_window [pid=$pinned_pid] move to workspace $focused_workspace"
else
	:
fi

