#!/bin/sh

mute=$(pamixer --get-mute)
if [ "$mute" = "true" ]; then
      volume=""
      icon=""
else 
      volume="$(pamixer --get-volume)"
      if [ "$volume" -gt 66 ]; then
            icon=""
      elif [ "$volume" -gt 33 ]; then
            icon=""
      elif [ "$volume" -gt 0 ]; then 
            icon=""
      else 
            icon=""
      fi
      volume="$volume%"
fi

echo "{\"content\": \"$volume\", \"icon\": \"$icon\"}"


