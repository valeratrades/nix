#!/usr/bin/env bash
# Move currently visible scratchpad to a different slot.
# If target slot is occupied, swap: move occupant to display (unmarked).
# Usage: scratchpad_move.sh <target_slot>

set -e

target_slot="${1:-0}"
state_file="/tmp/sway_scratchpad_visible"

# Get currently visible scratchpad
current_visible=""
if [ -f "$state_file" ]; then
    current_visible=$(cat "$state_file")
fi

# Exit if no scratchpad is currently visible
if [ -z "$current_visible" ]; then
    exit 0
fi

# Exit if trying to move to the same slot
if [ "$current_visible" = "$target_slot" ]; then
    exit 0
fi

# Check if target slot has windows
target_has_windows() {
    local count
    count=$(swaymsg -t get_tree | jq --arg mark "scratch_$target_slot" '
        [recurse(.nodes[], .floating_nodes[]) | select(.marks? and (.marks | index($mark)))] | length
    ')
    [ "$count" -gt 0 ]
}

# Remark current scratchpad windows to new slot
remark_scratchpad() {
    local from="$1"
    local to="$2"
    # Get all container IDs with the source mark
    local con_ids
    con_ids=$(swaymsg -t get_tree | jq -r --arg mark "scratch_$from" '
        [recurse(.nodes[], .floating_nodes[]) | select(.marks? and (.marks | index($mark))) | .id] | .[]
    ')
    for con_id in $con_ids; do
        swaymsg "[con_id=$con_id] unmark scratch_$from" 2>/dev/null || true
        swaymsg "[con_id=$con_id] mark --add scratch_$to" 2>/dev/null || true
    done
}

if target_has_windows; then
    # Swap: remark target to temp, current to target, temp to unmarked (displayed)
    # First, hide current scratchpad
    swaymsg "[con_mark=scratch_$current_visible] move scratchpad" 2>/dev/null || true

    # Bring up target slot windows and remove their marks (they become homeless)
    swaymsg "[con_mark=scratch_$target_slot] scratchpad show" 2>/dev/null || true
    # Get container IDs of target windows and unmark them
    target_con_ids=$(swaymsg -t get_tree | jq -r --arg mark "scratch_$target_slot" '
        [recurse(.nodes[], .floating_nodes[]) | select(.marks? and (.marks | index($mark))) | .id] | .[]
    ')
    for con_id in $target_con_ids; do
        swaymsg "[con_id=$con_id] unmark scratch_$target_slot" 2>/dev/null || true
    done

    # Remark the original current scratchpad to target slot
    remark_scratchpad "$current_visible" "$target_slot"

    # Clear state since the displaced windows are now visible but unmarked
    rm -f "$state_file"
else
    # Simple case: just remark current to target
    remark_scratchpad "$current_visible" "$target_slot"
    # Update state - the scratchpad is still visible, just with new slot number
    echo "$target_slot" > "$state_file"
fi
