#!/bin/sh
# File chooser wrapper for xdg-desktop-portal-termfilechooser
# Args: $1=multiple, $2=directory, $3=save, $4=path, $5=out, $6=debug

set -e
[ "${6:-0}" -ge 4 ] && set -x

multiple="$1"
directory="$2"
save="$3"
path="$4"
out="$5"

logfile="$HOME/.local/state/termfilechooser.log"
echo "$(date): multiple=$multiple, directory=$directory, save=$save, path=$path, out=$out" >> "$logfile"

if [ "$save" = "1" ]; then
  tmpfile=$(mktemp)
  statusfile=$(mktemp)
  echo "0" > "$statusfile"
  [ -n "$path" ] && echo "$path" > "$tmpfile" || echo "$HOME/newfile" > "$tmpfile"

  alacritty -e nvim "$tmpfile" "+TermFileChooserSave $statusfile"

  echo "$(date): After nvim exit, tmpfile contents: [$(cat "$tmpfile")]" >> "$logfile"
  if [ "$(cat "$statusfile")" = "1" ] && [ -f "$tmpfile" ] && [ -s "$tmpfile" ]; then
    selected_path=$(head -n1 "$tmpfile" | tr -d '\n\r')
    #HACK Create parent directory and touch the file so portal's stat() succeeds  {{{1
    mkdir -p "$(dirname "$selected_path")"
    touch "$selected_path"
    #,}}}1
    printf '%s' "$selected_path" > "$out"
    echo "$(date): SAVE CONFIRMED selected_path=$selected_path" >> "$logfile"
  else
    echo "$(date): SAVE ABORTED status=$(cat "$statusfile")" >> "$logfile"
  fi
  rm -f "$tmpfile" "$statusfile"
else
  tmpfile=$(mktemp)
  if [ -d "$path" ]; then
    startdir="$path"
  elif [ -n "$path" ]; then
    startdir=$(dirname "$path")
  else
    startdir="$HOME"
  fi

  alacritty -e nvim "$startdir" "+TermFileChooserOpen $tmpfile"

  if [ -f "$tmpfile" ] && [ -s "$tmpfile" ]; then
    cat "$tmpfile" > "$out"
    echo "$(date): OPEN CONFIRMED path=$(cat "$tmpfile")" >> "$logfile"
  else
    echo "$(date): OPEN ABORTED" >> "$logfile"
  fi
  rm -f "$tmpfile"
fi
