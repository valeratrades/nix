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
  # Open mode: use nvim to select a file
  # Create a temp buffer with file listing, user edits to just the file path
  tmpfile=$(mktemp)

  # Generate file list in the directory
  if [ -d "$suggestion" ]; then
    cd "$suggestion"
  else
    cd "$dir"
  fi

  # List files and put in temp file
  find . -maxdepth 3 -type f | sed 's|^\./||' > "$tmpfile"

  # Open nvim with mappings: q to quit without selecting, Enter to select
  alacritty -e nvim "$tmpfile" \
    -c 'nnoremap <CR> :.w!<CR>:qa!<CR>' \
    -c 'nnoremap q :qa!<CR>'

  # Get the selected line (written by <CR> mapping)
  selected=$(head -n 1 "$tmpfile" | tr -d '\n')
  if [ -n "$selected" ]; then
    # Make it an absolute path
    realpath "$selected" > "$out"
  fi

  rm -f "$tmpfile"
else
  # Save mode: let user edit the filename directly in nvim
  if [ -n "$suggestion" ]; then
    echo "$suggestion" > "$out"
  else
    echo "$dir/newfile" > "$out"
  fi

  # Open with q mapped to just exit, Enter to confirm and save
  alacritty -e nvim "$out" \
    -c 'nnoremap <CR> :wq<CR>' \
    -c 'nnoremap q :qa!<CR>'
fi
