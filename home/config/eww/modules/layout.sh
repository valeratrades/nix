#!/usr/bin/env sh
# default layout is semimak. If you wrote something in russian, you are expected to instantly switch back to semimak. Similar to `normal` mode in vim, - want to be able to assume at any time that current layout is semimak.

# Get the active layout name directly from swaymsg
current_layout=$(swaymsg -t get_inputs --raw | jq -r '[.[] | select(.xkb_active_layout_name != null) | .xkb_active_layout_name][0]')

# Map to abbreviations
case "$current_layout" in
  semimak*|Semimak*)
    echo ""
    ;;
  Russian|russian)
    echo "ru"
    ;;
  English*|english*)
    echo "en"
    ;;
  German*|german*)
    echo "de"
    ;;
  French*|french*)
    echo "fr"
    ;;
  Spanish*|spanish*)
    echo "es"
    ;;
  *)
    # For unknown layouts, take first 2 lowercase chars
    echo "$current_layout" | cut -c1-2 | tr '[:upper:]' '[:lower:]'
    ;;
esac
