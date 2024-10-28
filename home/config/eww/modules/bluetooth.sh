#!/bin/sh

# devices are: (1) headphones: Soundcore Life Tune, (2) headphones: Philips SHB3075
devices="""
E8:EE:CC:36:53:49
A4:77:58:82:26:43
"""

for device in $devices; do
  query=$(echo "info $device" | bluetoothctl)
  if echo "$query" | grep -q "Connected: yes"; then
		output=$(echo "info $device" | bluetoothctl | /usr/bin/rg "Battery Percentage" | awk -F '[()]' '{print $2}')

		if pactl list sources | grep -q "NoiseTorch"; then
			noisetorch="on"
		else
			noisetorch="off"
		fi

		case "$noisetorch" in
			"on")
				output="${output}"
				;;
		esac

		echo "$output"
		break
  fi
done
