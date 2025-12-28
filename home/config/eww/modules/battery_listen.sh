#!/usr/bin/env sh
# Event-based battery monitor for eww deflisten
# Outputs JSON only when battery state changes

battery="/sys/class/power_supply/BAT0/"
if [ ! -d "$battery" ]; then
  battery="/sys/class/power_supply/BATT/"
fi

last_output=""
f="$XDG_RUNTIME_DIR/battery_status"

while true; do
	percent=$(cat "$battery/capacity")
	adjusted_percent=$(awk -v val="$percent" 'BEGIN {printf "%d", int((val * 1.05) - 3 + 0.5)}')

	status=$(cat "$battery/status")

	icon=" "
	[ "$status" = "Charging" ] && icon=""
	[ "$status" = "Full" ] && adjusted_percent="100"
	[ "$status" = "Not charging" ] && adjusted_percent="100"

	# Low battery notification
	if [ "$adjusted_percent" -le 2 ] && [ ! -e "$f" ]; then
		echo "$percent" > "$f"
		notify-send -u critical "Battery low" "$percent% left" -t 999999
	fi
	if [ "$adjusted_percent" -ge 5 ] && [ -e "$f" ]; then
		rm -f "$f"
	fi

	output="{\"content\": \"$adjusted_percent\", \"icon\": \"$icon\"}"

	# Only emit when changed
	if [ "$output" != "$last_output" ]; then
		echo "$output"
		last_output="$output"
	fi

	sleep 5
done
