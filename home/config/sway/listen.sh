#!/bin/bash
swaymsg -t subscribe '["workspace"]' | jq -c --unbuffered '
  select(.change == "focus") |
  if .current and .current.name == "3" then
    "resume"
  elif .old and .old.name == "3" then
    "suspend"
  else
    empty
  end
' | while read -r action; do
  case "$action" in
    "resume") pkill -CONT -f "/usr/bin/discord" ;;
    "suspend") pkill -STOP -f "/usr/bin/discord" ;;
  esac
done

