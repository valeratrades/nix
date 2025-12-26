#!/usr/bin/env bash
# Toggle a specific scratchpad (0-9). Hides any currently visible scratchpad first.
# Usage: scratchpad_toggle.sh <index> [--create-if-empty]

set -e

index="${1:-0}"
create_if_empty="${2:-}"
state_file="/tmp/sway_scratchpad_visible"

# Get currently visible scratchpad (if any)
current_visible=""
if [ -f "$state_file" ]; then
    current_visible=$(cat "$state_file")
fi

# Check if requested scratchpad has any windows
has_windows() {
    local idx="$1"
    local count
    count=$(swaymsg -t get_tree | jq --arg mark "scratch_$idx" '
        [recurse(.nodes[], .floating_nodes[]) | select(.marks? and (.marks | index($mark)))] | length
    ')
    [ "$count" -gt 0 ]
}

# Check if a scratchpad window is currently visible (not in scratchpad state)
is_visible() {
    local idx="$1"
    swaymsg -t get_tree | jq --arg mark "scratch_$idx" -e '
        [recurse(.nodes[], .floating_nodes[])
         | select(.marks? and (.marks | index($mark)))
         | select(.scratchpad_state == "none" or .scratchpad_state == null)] | length > 0
    ' > /dev/null 2>&1
}

# Hide scratchpad by moving its windows back to scratchpad
hide_scratchpad() {
    local idx="$1"
    swaymsg "[con_mark=scratch_$idx] move scratchpad" 2>/dev/null || true
}

# Show scratchpad
show_scratchpad() {
    local idx="$1"
    swaymsg "[con_mark=scratch_$idx] scratchpad show" 2>/dev/null || true
}

# Create a new terminal for the main scratchpad
create_main_scratchpad() {
    swaymsg exec alacritty
    swaymsg -t subscribe '["window"]' | jq -c --unbuffered 'select(.change == "focus")' | head -n1 > /dev/null
    sleep 0.1
    swaymsg mark scratch_0
    swaymsg move scratchpad
    swaymsg scratchpad show
}

# If same scratchpad is requested and it's visible, hide it
if [ "$current_visible" = "$index" ] && is_visible "$index"; then
    hide_scratchpad "$index"
    rm -f "$state_file"
    exit 0
fi

# Hide currently visible scratchpad if different
if [ -n "$current_visible" ] && [ "$current_visible" != "$index" ]; then
    hide_scratchpad "$current_visible"
fi

# Show requested scratchpad
if has_windows "$index"; then
    show_scratchpad "$index"
    echo "$index" > "$state_file"
elif [ "$create_if_empty" = "--create-if-empty" ] && [ "$index" = "0" ]; then
    create_main_scratchpad
    echo "0" > "$state_file"
else
    # No windows in this scratchpad slot
    rm -f "$state_file"
fi
