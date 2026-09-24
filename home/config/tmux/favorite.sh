#!/bin/sh
# Toggles the `*` favorite prefix on a session. `$1`: session name or choose-tree target (`=name:`); `$2`: pane to reopen choose-tree in, with the cursor on the session
n=${1#=}
n=${n%:}
case "$n" in
\**) new=${n#?} ;;
*) new="*$n" ;;
esac
tmux rename-session -t "=$n" "$new"
[ -z "$2" ] && exit 0
rank=$(tmux list-sessions -F '#S' | LC_ALL=C sort | grep -nxF -- "$new" | cut -d: -f1) # choose-tree -O name is strcmp
tmux run-shell -t "$2" -C favtree
tmux send-keys -t "$2" g
if [ "$rank" -gt 1 ]; then tmux send-keys -t "$2" -N $((rank - 1)) Down; fi
