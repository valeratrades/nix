#!/bin/bash

# Check pipe status and return appropriate values
# Main line: show "None" if no changes in last 60s
# Additional line: show "None" if no changes in last 15m

STATE_DIR="$HOME/.local/state/btc_line"
MAIN_FILE="$STATE_DIR/main"
ADDITIONAL_FILE="$STATE_DIR/additional"
TIMESTAMPS_FILE="$STATE_DIR/.timestamps"

# Get current time
CURRENT_TIME=$(date +%s)

# Function to get timestamp from .timestamps file
get_timestamp() {
    local name="$1"
    if [ -f "$TIMESTAMPS_FILE" ]; then
        # Extract timestamp for the given name
        local line=$(grep "^${name}: " "$TIMESTAMPS_FILE")
        if [ -n "$line" ]; then
            # Split on ": " and get the datetime
            local datetime=$(echo "$line" | cut -d':' -f2- | sed 's/^ //')
            # Convert ISO8601 to unix timestamp
            date -d "$datetime" +%s 2>/dev/null || echo 0
        else
            echo 0
        fi
    else
        echo 0
    fi
}

# Function to read value from file
read_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cat "$file" 2>/dev/null | tr -d '\n'
    else
        echo ""
    fi
}

# Check main (60 seconds threshold)
main_timestamp=$(get_timestamp "main")
main_age=$((CURRENT_TIME - main_timestamp))

if [ $main_age -gt 60 ]; then
    main_value="None"
else
    main_value=$(read_file "$MAIN_FILE")
    [ -z "$main_value" ] && main_value=""
fi

# Check additional (15 minutes = 900 seconds threshold)
additional_timestamp=$(get_timestamp "additional")
additional_age=$((CURRENT_TIME - additional_timestamp))

if [ $additional_age -gt 900 ]; then
    additional_value="None"
else
    additional_value=$(read_file "$ADDITIONAL_FILE")
    [ -z "$additional_value" ] && additional_value=""
fi

# Output the values as JSON
echo "{\"main\": \"$main_value\", \"additional\": \"$additional_value\"}"
