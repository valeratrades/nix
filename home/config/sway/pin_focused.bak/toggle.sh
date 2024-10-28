#!/bin/sh

file_path="${HOME}/.config/sway/pin_focused/pid.txt"

if [ -f "$file_path" ]; then
  rm "$file_path"
else
  window_info=$(swaymsg -t get_tree | jq -r '.. | (.nodes? // empty)[] | select(.focused==true) .pid')
  mkdir $(dirname "$file_path")
  echo "$window_info" > "$file_path"
fi

