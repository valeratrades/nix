#!/usr/bin/env bash
# Assign current window to the first available scratchpad slot (0-9)
# Usage: scratchpad_assign.sh

set -e

# Get count of windows in each scratchpad slot
get_slot_count() {
    local idx="$1"
    swaymsg -t get_tree | jq --arg mark "scratch_$idx" '
        [recurse(.nodes[], .floating_nodes[]) | select(.marks? and (.marks | index($mark)))] | length
    '
}

# Find first empty slot
find_empty_slot() {
    for i in $(seq 0 9); do
        local count
        count=$(get_slot_count "$i")
        if [ "$count" -eq 0 ]; then
            echo "$i"
            return 0
        fi
    done
    # All slots full, use slot 0 as fallback
    echo "0"
}

# Remove any existing scratch marks from focused window
for i in $(seq 0 9); do
    swaymsg "[con_id=__focused__] unmark scratch_$i" 2>/dev/null || true
done

slot=$(find_empty_slot)
swaymsg mark "scratch_$slot"
swaymsg move scratchpad
