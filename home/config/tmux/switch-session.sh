#!/bin/bash

CONF="$HOME/.config/tmux/sessions"

selected="$1"
[ -z "$selected" ] && selected=$(~/.config/jfind/jfind-session.sh)
[ -z "$selected" ] && exit;

color=$(awk '/^'"$selected"' /{print $2}' "$CONF")

session_exists() {
    tmux list-sessions -F "#S" | grep "^$selected$" &>/dev/null
}

session_exists || \
    "$HOME/.config/tmux/create-session.sh" "$selected"

tmux switch-client -t "$selected"
tmux set-environment session_color "$color"
