#!/bin/bash

# move_workspace_layout.sh - Copy workspace structure and move all containers to another workspace
# Usage: ./move_workspace_layout.sh <source_workspace> <target_workspace>

if [ $# -ne 2 ]; then
    echo "Usage: $0 <source_workspace> <target_workspace>"
    echo "Example: $0 1 2"
    exit 1
fi

SOURCE_WS="$1"
TARGET_WS="$2"
LAYOUT_FILE="/tmp/sway_layout_${SOURCE_WS}_to_${TARGET_WS}.json"

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    exit 1
fi

# Function to get workspace tree structure
get_workspace_tree() {
    local workspace="$1"
    swaymsg -t get_tree | jq ".nodes[] | recurse(.nodes[]?) | select(.type == \"workspace\" and .name == \"$workspace\")"
}

# Function to save detailed layout structure
save_layout_structure() {
    local workspace="$1"
    local layout_file="$2"
    
    echo "Capturing layout structure from workspace $workspace..."
    
    # Get the complete workspace structure and save to file  
    swaymsg -t get_tree | jq --arg workspace "$workspace" '
        def recurse_down:
            {
                id: .id,
                type: .type,
                layout: .layout,
                orientation: .orientation,
                app_id: .app_id,
                window_properties: .window_properties,
                name: .name,
                percent: .percent,
                has_children: (.nodes | length > 0),
                nodes: [.nodes[]? | recurse_down]
            };
        
        .nodes[] | 
        recurse(.nodes[]?) | 
        select(.type == "workspace" and .name == $workspace) |
        {
            type: .type,
            layout: .layout,
            orientation: .orientation,
            nodes: [.nodes[] | recurse_down]
        }
    ' > "$layout_file"
    
    echo "Layout structure saved to $layout_file"
}

# Function to move all containers from source to target workspace
move_containers() {
    local source="$1"
    local target="$2"
    
    # Get all container IDs in the source workspace
    local container_ids=$(swaymsg -t get_tree | jq -r "
        .nodes[] | 
        recurse(.nodes[]?) | 
        select(.type == \"workspace\" and .name == \"$source\") |
        .. |
        select(type == \"object\" and has(\"type\") and .type == \"con\" and (has(\"app_id\") or has(\"window_properties\"))) |
        .id
    ")
    
    if [ -z "$container_ids" ]; then
        echo "No containers found in workspace $source"
        return
    fi
    
    # Switch to target workspace first
    swaymsg "workspace $target"
    
    # Move each container
    while IFS= read -r container_id; do
        if [ -n "$container_id" ]; then
            swaymsg "[con_id=$container_id] move container to workspace $target"
        fi
    done <<< "$container_ids"
}

# Function to recreate layout structure from saved file
recreate_layout_structure() {
    local layout_file="$1"
    local target_workspace="$2"
    
    if [ ! -f "$layout_file" ]; then
        echo "Layout file $layout_file not found"
        return 1
    fi
    
    echo "Recreating layout structure in workspace $target_workspace..."
    
    # Switch to target workspace
    swaymsg "workspace $target_workspace"
    
    # Get all container IDs currently in the target workspace (the moved containers)
    local moved_containers=($(swaymsg -t get_tree | jq -r "
        .nodes[] | 
        recurse(.nodes[]?) | 
        select(.type == \"workspace\" and .name == \"$target_workspace\") |
        .. |
        select(type == \"object\" and has(\"type\") and .type == \"con\" and (has(\"app_id\") or has(\"window_properties\"))) |
        .id
    "))
    
    if [ ${#moved_containers[@]} -eq 0 ]; then
        echo "No containers found in target workspace to arrange"
        return 1
    fi
    
    # Apply the layout structure recursively
    apply_layout_recursive "$layout_file" "${moved_containers[@]}"
    
    echo "Layout structure recreated successfully"
}

# Function to apply layout recursively based on saved structure
apply_layout_recursive() {
    local layout_file="$1"
    shift
    local containers=("$@")
    
    # Get the root layout
    local root_layout=$(jq -r '.layout' "$layout_file")
    
    # Start with first container focused
    if [ ${#containers[@]} -gt 0 ]; then
        swaymsg "[con_id=${containers[0]}] focus"
    fi
    
    # Apply splits based on the saved structure
    recreate_splits "$layout_file" ".nodes" "${containers[@]}"
}

# Function to recursively create splits
recreate_splits() {
    local layout_file="$1"
    local node_path="$2"
    shift 2
    local containers=("$@")
    
    # Get children at this level
    local children_count=$(jq -r "${node_path} | length" "$layout_file" 2>/dev/null)
    
    if [ -z "$children_count" ] || [ "$children_count" = "null" ] || [ "$children_count" -le 1 ]; then
        return
    fi
    
    # For each child that has its own children (containers), create appropriate splits
    for ((i=0; i<children_count; i++)); do
        local child_layout=$(jq -r "${node_path}[$i].layout" "$layout_file")
        local child_has_children=$(jq -r "${node_path}[$i].has_children" "$layout_file")
        
        if [ "$child_has_children" = "true" ] && [ $i -lt ${#containers[@]} ]; then
            # Focus the container we want to split
            swaymsg "[con_id=${containers[$i]}] focus"
            
            # Create the appropriate split
            case "$child_layout" in
                "splith")
                    if [ $((i+1)) -lt ${#containers[@]} ]; then
                        swaymsg "split horizontal"
                    fi
                    ;;
                "splitv")
                    if [ $((i+1)) -lt ${#containers[@]} ]; then
                        swaymsg "split vertical"
                    fi
                    ;;
                "tabbed")
                    swaymsg "layout tabbed"
                    ;;
                "stacking")
                    swaymsg "layout stacking"
                    ;;
            esac
            
            # Recursively handle children
            recreate_splits "$layout_file" "${node_path}[$i].nodes" "${containers[@]:$i}"
        fi
    done
}

# Main execution
echo "Moving workspace layout from $SOURCE_WS to $TARGET_WS..."

# Step 1: Save the layout structure before moving anything
save_layout_structure "$SOURCE_WS" "$LAYOUT_FILE"

# Step 2: Move all containers to target workspace
echo "Moving all containers from workspace $SOURCE_WS to $TARGET_WS..."
move_containers "$SOURCE_WS" "$TARGET_WS"

# Step 3: Recreate the exact layout structure
echo "Recreating layout structure..."
recreate_layout_structure "$LAYOUT_FILE" "$TARGET_WS"

# Clean up
rm -f "$LAYOUT_FILE"

echo "Workspace migration complete!"
echo "All containers from workspace $SOURCE_WS have been moved to workspace $TARGET_WS with preserved layout"

# Switch to the target workspace to see the result
swaymsg "workspace $TARGET_WS" >/dev/null
