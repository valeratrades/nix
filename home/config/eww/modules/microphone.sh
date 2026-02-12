#!/usr/bin/env sh

mute=$(pamixer --default-source --get-mute)

if [ "$mute" = "true" ]; then
	volume=""
	icon=""
else 
	volume=$(pamixer --default-source --get-volume)
	icon=""
fi

echo "{\"content\": \"$volume\", \"icon\": \"$icon\", \"muted\": \"$mute\"}"
