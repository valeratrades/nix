#!/bin/sh

mute=$(pamixer --default-source --get-mute)

if [ "$mute" = "true" ]; then
	volume=""
	icon=""
else 
	volume=$(pamixer --default-source --get-volume)
	icon=""
fi

#if [ -n "$volume" ] && [ "$volume" -gt 40 ]; then
#	volume="30"
#fi

echo "{\"content\": \"$volume\", \"icon\": \"$icon\"}"
