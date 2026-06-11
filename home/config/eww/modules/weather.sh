#!/usr/bin/env sh

# Current weather via wttr.in (geo-IP location, no API key needed).
# Output: {"icon": "<condition glyph><thermometer>", "content": "<temp>"}
# On any failure we serve the last good cache, and only emit empty (-> widget
# hidden) if we never managed to fetch once. No stale-but-pretending-fresh data.

cache="$XDG_RUNTIME_DIR/eww_weather.json"

# WWO weatherCode -> Nerd Font weather glyph.
# https://github.com/chubin/wttr.in/blob/master/lib/constants.py
icon_for() {
	case "$1" in
		113) echo "" ;;
		116) echo "" ;;
		119|122) echo "" ;;
		143|248|260) echo "" ;;
		176|263|266|293|296|353) echo "" ;;
		299|302|305|308|356|359) echo "" ;;
		179|182|185|227|230|317|320|323|326|329|332|335|338|350|362|365|368|371|374|377) echo "" ;;
		200|386|389|392|395) echo "" ;;
		*) echo "" ;;
	esac
}

raw=$(timeout 8 curl -s 'wttr.in/?format=j1' 2>/dev/null)

if [ -n "$raw" ]; then
	parsed=$(printf '%s' "$raw" | jq -c '.current_condition[0] | {temp: .temp_C, code: .weatherCode}' 2>/dev/null)
	if [ -n "$parsed" ] && [ "$parsed" != "null" ]; then
		temp=$(printf '%s' "$parsed" | jq -r '.temp')
		code=$(printf '%s' "$parsed" | jq -r '.code')
		out="{\"icon\": \"$(icon_for "$code")\", \"content\": \"${temp}\"}"
		printf '%s' "$out" > "$cache"
		echo "$out"
		exit 0
	fi
fi

# Fetch failed: fall back to last good value, or stay hidden.
if [ -f "$cache" ]; then
	cat "$cache"
else
	echo "{\"icon\": \"\", \"content\": \"\"}"
fi
