#!/usr/bin/env bash
# Rofi interface for ringboard clipboard manager
# Shows clipboard history, allows selection to paste

set -euo pipefail

# Get all entries from ringboard
entries=$(ringboard debug dump 2>/dev/null)

if [ "$entries" = "[]" ] || [ -z "$entries" ]; then
    notify-send "Ringboard" "Clipboard is empty"
    exit 0
fi

# Parse JSON and create rofi menu
# Format: ID | first 80 chars of content (newlines replaced with spaces)
menu=$(echo "$entries" | jq -r '.[] | "\(.id)\t\(.data | gsub("\n"; " ") | if length > 80 then .[:80] + "..." else . end)"')

if [ -z "$menu" ]; then
    notify-send "Ringboard" "No text entries found"
    exit 0
fi

# Show rofi menu in floating window
selected=$(echo "$menu" | rofi -dmenu -i -p "Clipboard" -format 'i:s' -no-custom -window-title "rofi-clipboard" 2>/dev/null) || exit 0

if [ -z "$selected" ]; then
    exit 0
fi

# Extract the ID (first field before tab)
id=$(echo "$menu" | sed -n "$((${selected%%:*} + 1))p" | cut -f1)

if [ -n "$id" ]; then
    # Get full content and copy to clipboard
    ringboard get "$id" | wl-copy
    # Move to front so it becomes the most recent
    ringboard move-to-front "$id"
fi
