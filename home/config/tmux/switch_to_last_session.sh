#!/usr/bin/env bash
# Switch to the most recently active session (by last attached time)
# Excludes the current session

current_session=$(tmux display-message -p '#{session_name}')

# Get all sessions except current, sorted by last_attached time (descending)
# Format: last_attached_timestamp session_name
last_session=$(tmux list-sessions -F "#{session_last_attached} #{session_name}" \
    | grep -v " ${current_session}$" \
    | sort -rn \
    | head -1 \
    | awk '{print $2}')

if [ -n "$last_session" ]; then
    tmux switch-client -t "$last_session"
else
    # No other session found, show session chooser
    tmux choose-tree -Zs
fi
