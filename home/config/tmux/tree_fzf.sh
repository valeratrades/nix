#!/bin/sh
# fzf session picker over choose-tree. `$1`: the tree's pane; `$2`: its client
s=$(tmux list-sessions -F '#S' | fzf --preview 'tmux capture-pane -ep -t ={}:') || exit 0
tmux send-keys -t "$1" q \; switch-client -c "$2" -Zt "=$s:"
