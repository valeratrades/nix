#!/bin/sh

battery="/sys/class/power_supply/BAT0/"
percent=$(cat "$battery/capacity")
adjusted_percent=$(awk -v val=$percent 'BEGIN {printf "%d", int((val * 1.05) - 3 + 0.5)}') # This is changing due to the age of the battery, so practically an eyeball

status=$(cat "$battery/status")

icon=" "
[ "$status" = "Charging" ] && icon=""
[ "$status" = "Full" ] && adjusted_percent="100"
[ "$status" = "Not charging" ] && adjusted_percent="100" # happens when we're fully charged but still plugged.

echo "{\"content\": \"$adjusted_percent\", \"icon\": \"$icon\"}"
