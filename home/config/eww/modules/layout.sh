#!/usr/bin/env sh
# default layout is semimak. If you wrote something in russian, you are expected to instantly switch back to semimak. Similar to `normal` mode in vim, - want to be able to assume at any time that current layout is semimak.

# Get the active layout name directly from swaymsg
current_layout=$(swaymsg -t get_inputs --raw | jq -r '[.[] | select(.xkb_active_layout_name != null) | .xkb_active_layout_name][0]')

# Normalize: semimak variants (ANSI, ISO, etc.) should all be treated as semimak
case "$current_layout" in
  semimak*|Semimak*)
    echo ""
    ;;
  *)
    echo "$current_layout"
    ;;
esac
