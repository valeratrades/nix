#!/bin/sh
# File chooser wrapper for xdg-desktop-portal-termfilechooser
# This is called by the portal with these arguments:
# $1 = directory (optional)
# $2 = multiple selection (0 or 1)
# $3 = save mode (0 = open, 1 = save)
# $4 = suggestion (filename when saving)
# $5 = output file path

dir="${1:-$HOME}"
multiple="$2"
save="$3"
suggestion="$4"
out="$5"

# Debug notifications (comment out if annoying)
# notify-send "termfilechooser" "save: $save, dir: $dir, suggestion: $suggestion"

if [ "$save" -eq 1 ]; then
  # Save mode: let user edit the filename directly in nvim
  if [ -n "$suggestion" ]; then
    echo "$suggestion" > "$out"
  else
    echo "$dir/newfile" > "$out"
  fi
  alacritty -e nvim "$out"
else
  # Open mode: use yazi for file selection
  # yazi outputs selected file(s) to stdout when using --chooser-file
  alacritty -e sh -c "cd '$dir' && yazi --chooser-file='$out'"
fi
