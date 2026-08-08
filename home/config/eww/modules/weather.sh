#!/usr/bin/env sh

# Current weather via open-meteo, coords from ipinfo.io geo-IP (no API keys).
# Geo-IP is wrong on mobile (CGNAT egresses at the carrier hub, eg Orange -> Lyon);
# write "lat,lon" to ~/.config/eww/location to override. An override outlives the trip
# it was written for, so it renders with a  and never passes for a geo-IP reading.
# wttr.in was dropped: when its geo-IP lookup fails it silently serves its
# default location (central Paris) instead of erroring.
# Output: {"icon": "<condition glyph>", "content": "<temp>"}
# On any failure: "_", never a stale or wrong value.

# WMO weather code -> Nerd Font weather glyph.
# https://open-meteo.com/en/docs#weather_variable_documentation
icon_for() {
	case "$1" in
		0) echo "" ;;
		1|2) echo "" ;;
		3) echo "" ;;
		45|48) echo "" ;;
		51|53|55|56|57|61|63|80|81) echo "" ;;
		65|66|67|82) echo "" ;;
		71|73|75|77|85|86) echo "" ;;
		95|96|99) echo "" ;;
		*) echo "" ;;
	esac
}

loc=$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/eww/location" 2>/dev/null | tr -d '[:space:]')
pin=""
[ -n "$loc" ] && pin=""
[ -z "$loc" ] && loc=$(timeout 5 curl -s 'https://ipinfo.io/loc' 2>/dev/null | tr -d '[:space:]')
case "$loc" in
	*[0-9],*[0-9]*)
		lat=${loc%,*}
		lon=${loc#*,}
		raw=$(timeout 8 curl -s "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code" 2>/dev/null)
		parsed=$(printf '%s' "$raw" | jq -c '.current | {temp: (.temperature_2m | round), code: .weather_code}' 2>/dev/null)
		if [ -n "$parsed" ] && [ "$parsed" != "null" ]; then
			temp=$(printf '%s' "$parsed" | jq -r '.temp')
			code=$(printf '%s' "$parsed" | jq -r '.code')
			echo "{\"icon\": \"$(icon_for "$code")$pin\", \"content\": \"${temp}\"}"
			exit 0
		fi
		;;
esac

echo '{"icon": "", "content": "_"}'
