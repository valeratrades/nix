#!/usr/bin/env dash
#XXX: does not work
#DEPRECATE: if a working option is implemented elsewhere

# Copy the layout (and all windows) of the currently focused workspace
# into another workspace by numeric id. Requires: swaymsg, jq.
sway_copy_layout_to_ws() {
	[ -n "$1" ] || { printf "usage: sway_copy_layout_to_ws <workspace-number>\n" >&2; return 2; }
	target="$1"

	wsname="$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused).name')"
	[ -n "$wsname" ] || { printf "error: could not determine focused workspace\n" >&2; return 1; }

	tree="$(swaymsg -t get_tree)"

	layout="$(printf '%s' "$tree" | jq -r --arg ws "$wsname" '
		.. | objects | select(.type=="workspace" and .name==$ws) | .layout
	')"

	# Top-level tiling containers (preserve order)
	ids="$(printf '%s' "$tree" | jq -r --arg ws "$wsname" '
		.. | objects | select(.type=="workspace" and .name==$ws) | .nodes[]?.id
	')"

	# Floating windows
	fids="$(printf '%s' "$tree" | jq -r --arg ws "$wsname" '
		.. | objects | select(.type=="workspace" and .name==$ws) | .floating_nodes[]?.id
	')"

	# Prepare destination workspace with same top-level layout
	swaymsg "workspace number $target; layout $layout" >/dev/null

	# Move tiling containers
	for id in $ids; do
		swaymsg "[con_id=$id]" "move container to workspace number $target" >/dev/null
	done

	# Move floating containers
	for id in $fids; do
		swaymsg "[con_id=$id]" "move container to workspace number $target" >/dev/null
	done

	# Jump to the new workspace
	swaymsg "workspace number $target" >/dev/null
}

