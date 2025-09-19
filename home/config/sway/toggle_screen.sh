#!/usr/bin/env sh
# `jq -e` will exit with exitcode=1 if final value is false.
OUTPUT="$1"
if swaymsg -t get_outputs -r | jq -e ".[] | select(.name==\"$OUTPUT\") | .active"; then
  swaymsg output "$OUTPUT" disable
  echo "Disabled"
else
  swaymsg output "$OUTPUT" enable
  echo "Enabled"
fi

