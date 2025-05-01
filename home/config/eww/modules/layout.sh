#!/usr/bin/env sh
# default layout is semimak. If you wrote something in russian, you are expected to instantly switch back to semimak. Similar to `normal` mode in vim, - want to be able to assume at any time that current layout is semimak.

index=$(swaymsg -t get_inputs | grep "xkb_active_layout_index" | head -1 | awk '{print $2}' | tr -d ',')

layouts=$(localectl status | grep "X11 Layout" | awk '{print $3}')

line_number=$(( index + 1 ))
current_layout=$(echo "$layouts" | tr ',' '\n' | sed -n "${line_number}p")

if [ "$current_layout" = "semimak" ]; then
  echo ""
else
  echo "$current_layout"
fi
