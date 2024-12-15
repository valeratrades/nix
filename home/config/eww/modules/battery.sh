#!/usr/bin/env sh

battery="/sys/class/power_supply/BAT0/"
if [ ! -d "$battery" ]; then
  battery="/sys/class/power_supply/BATT/"
fi

percent=$(cat "$battery/capacity")
adjusted_percent=$(awk -v val=$percent 'BEGIN {printf "%d", int((val * 1.05) - 3 + 0.5)}')

status=$(cat "$battery/status")

icon=" "
[ "$status" = "Charging" ] && icon=""
[ "$status" = "Full" ] && adjusted_percent="100"
[ "$status" = "Not charging" ] && adjusted_percent="100"

echo "{\"content\": \"$adjusted_percent\", \"icon\": \"$icon\"}"
