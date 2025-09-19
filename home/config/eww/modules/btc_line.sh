#!/bin/bash

# Check pipe status and return appropriate values
# Main line: show "None" if no changes in last 60s
# Additional line: show "None" if no changes in last 15m

PIPE_DIR="/tmp/btc_line"
MAIN_PIPE="$PIPE_DIR/main"
ADDITIONAL_PIPE="$PIPE_DIR/additional"

# Get current time
CURRENT_TIME=$(date +%s)

# Function to get file modification time
get_mtime() {
    if [ -e "$1" ]; then
        stat -c %Y "$1" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# Function to safely read from pipe with timeout
read_pipe() {
    local pipe="$1"
    if [ -p "$pipe" ]; then
        # Try to read with timeout to avoid blocking
        timeout 0.1 cat "$pipe" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Check main pipe (60 seconds threshold)
main_mtime=$(get_mtime "$MAIN_PIPE")
main_age=$((CURRENT_TIME - main_mtime))

if [ $main_age -gt 60 ]; then
    main_value="None"
else
    # Try to read current value from pipe
    main_value=$(read_pipe "$MAIN_PIPE")
    [ -z "$main_value" ] && main_value=""
fi

# Check additional pipe (15 minutes = 900 seconds threshold)
additional_mtime=$(get_mtime "$ADDITIONAL_PIPE")
additional_age=$((CURRENT_TIME - additional_mtime))

if [ $additional_age -gt 1860 ]; then
    additional_value="None"
else
    # Try to read current value from pipe
    additional_value=$(read_pipe "$ADDITIONAL_PIPE")
    [ -z "$additional_value" ] && additional_value=""
fi

# Output the values as JSON
echo "{\"main\": \"$main_value\", \"additional\": \"$additional_value\"}"
