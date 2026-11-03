#!/bin/sh
# fzf session picker. `$1`: client to switch; `$2`: choose-tree pane to quit, or empty; `$3`: initial query
s=$(tmux list-sessions -F '#S' | fzf --query "$3" --preview 'tmux capture-pane -ep -t ={}:') || exit 0
[ -n "$2" ] && tmux send-keys -t "$2" q
tmux switch-client -c "$1" -Zt "=$s:"
