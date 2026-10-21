#!/usr/bin/env bash
# Our players (mpv, timer, ambiance) playing dominate the toggle; the ones we paused are resumed on the next toggle.
set -uo pipefail

cache="${XDG_CACHE_HOME:-$HOME/.cache}/play_pause_ours_paused"
obj=/org/mpris/MediaPlayer2
iface=org.mpris.MediaPlayer2.Player

status() { busctl --user get-property "$1" $obj $iface PlaybackStatus 2>/dev/null; } # empty if the instance is gone

mapfile -t ours < <(busctl --user list --no-legend | awk '$1 ~ /^org\.mpris\.MediaPlayer2\.(mpv|timer|ambiance)(\.|$)/ {print $1}')

playing=()
for p in "${ours[@]}"; do
	[ "$(status "$p")" = 's "Playing"' ] && playing+=("$p")
done
if [ ${#playing[@]} -gt 0 ]; then
	for p in "${playing[@]}"; do busctl --user call "$p" $obj $iface Pause; done
	printf '%s\n' "${playing[@]}" >"$cache"
	exit 0
fi

if [ -f "$cache" ]; then
	mapfile -t paused <"$cache"
	rm "$cache"
	# something else started playing since we paused ours: toggle means "pause that", not "resume ours"
	if ! playerctl -a status 2>/dev/null | grep -qx Playing; then
		resumed=0
		for p in "${paused[@]}"; do
			[ "$(status "$p")" = 's "Paused"' ] && busctl --user call "$p" $obj $iface Play && resumed=1
		done
		[ $resumed = 1 ] && exit 0
	fi
fi

exec playerctl play-pause
