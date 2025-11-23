#!/usr/bin/env bash
# Opens eww windows on the currently focused Sway output/monitor

# Get the focused output name
focused_output=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused == true) | .name')

# Map output name to eww monitor index (default to 0 if not found)
monitor_index=$(swaymsg -t get_outputs | jq --arg output "$focused_output" -r '
    [.[] | select(.active == true)] |
    sort_by(.rect.x, .rect.y) |
    to_entries |
    .[] |
    select(.value.name == $output) |
    .key // 0
') || monitor_index=0

echo "Opening eww windows on monitor $monitor_index"

# Open windows with explicit screen parameter
eww open bar --screen "$monitor_index"
eww open btc_line_lower --screen "$monitor_index"
eww open btc_line_upper --screen "$monitor_index"
eww open todo_blocker --screen "$monitor_index"
