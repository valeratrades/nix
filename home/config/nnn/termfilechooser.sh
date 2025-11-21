#!/bin/sh
# File chooser wrapper for xdg-desktop-portal-termfilechooser
# Arguments from portal: $1=dir, $2=multiple, $3=save, $4=suggestion, $5=output_file
# save=0 means OPEN, save=1 means SAVE

dir="${1:-$HOME}"
multiple="$2"
save="$3"
suggestion="$4"
out="$5"

# Debug notifications (uncomment to debug)
# notify-send "termfilechooser" "save: $save, dir: $dir, suggestion: $suggestion, out: $out"

if [ "$save" -eq 0 ]; then
  # Open mode: use yazi for file selection
  # yazi --chooser-file writes selected file path(s) to the output file
  alacritty -e sh -c "cd '$dir' && yazi --chooser-file='$out'"
else
  # Save mode: let user edit the filename directly in nvim
  if [ -n "$suggestion" ]; then
    echo "$suggestion" > "$out"
  else
    echo "$dir/newfile" > "$out"
  fi
  alacritty -e nvim "$out"
fi
