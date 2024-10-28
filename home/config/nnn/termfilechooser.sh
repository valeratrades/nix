#!/bin/sh
#dbg
notify-send "save: $3"
notify-send "suggestion: $4"
notify-send "out: $5"

# to see which xdg-desktop is being used, do:
# dbus-monitor "interface=org.freedesktop.portal.FileChooser" | tee ~/xdg-portal.log

# binary. If it's us sending, - `0`, otherwise `1`
save="$3"
# often present when saving; is a full filepath
suggestion="$4"
# out is always /tmp/termfilechooser
out="$5"

if [ "$save" -eq 0 ]; then
  alacritty -e nnn -p "$out"
else
	echo "/home/v/Downloads/$(basename $suggestion)" > "$out"
  alacritty -e nvim "$out"
fi


#st -c picker sh -c "nnn -p - '$suggest' | awk '{ print system(\"[ -d '\''\"\$0\"'\'' ]\") ? \$0 : \$0\"/$file\" }' > '$out'"
