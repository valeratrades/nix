#!/bin/bash

# Check pipe status and return appropriate values
# Main line: show "None" if no changes in last 60s
# Additional line: show "None" if no changes in last 15m

STATE_DIR="$HOME/.local/state/btc_line"
MAIN_FILE="$STATE_DIR/main"
ADDITIONAL_FILE="$STATE_DIR/additional"
SPY_FILE="$STATE_DIR/spy"
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

# Function to restore value if needed
# Args: line_name, max_age_seconds, file_path
restore_if_needed() {
    local name="$1"
    local max_age="$2"
    local file="$3"

    # Get timestamp and check freshness
    local timestamp=$(get_timestamp "$name")
    local age=$((CURRENT_TIME - timestamp))

    # Only proceed if data is fresh enough
    if [ $age -le $max_age ]; then
        # Check if eww variable is empty
        local eww_var="btc_line_${name}_str"
        local current_value=$(eww get "$eww_var" 2>/dev/null)

        # If empty, restore from file
        if [ -z "$current_value" ] && [ -f "$file" ]; then
            local file_value=$(read_file "$file")
            if [ -n "$file_value" ]; then
                eww update "${eww_var}=${file_value}"
            fi
        fi
    fi
}

# Restore values on startup if they're fresh and not already set
restore_if_needed "main" 60 "$MAIN_FILE"
restore_if_needed "additional" 900 "$ADDITIONAL_FILE"
restore_if_needed "spy" 60 "$SPY_FILE"

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
