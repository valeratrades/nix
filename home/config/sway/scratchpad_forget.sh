#!/usr/bin/env bash
# Remove all scratchpad marks from the focused window, so it's no longer
# considered part of any scratchpad slot.
# Usage: scratchpad_forget.sh

set -e

for i in $(seq 0 9); do
    swaymsg "[con_id=__focused__] unmark scratch_$i" 2>/dev/null || true
done
