#!/bin/sh
# fzf session picker. `$1`: client to switch; `$2`: choose-tree pane to quit, or empty; `$3`: initial query
s=$(~/nix/home/scripts/claude_sessions/main.rs --cached --targets --fzf 2>/dev/null |
	awk -F '\t' -v live="$(tmux list-windows -a -F '#{session_id}:#{window_id}')" -v sessions="$(tmux list-sessions -F '#{session_id}:	#{session_name}:last')" '
		BEGIN { n = split(live, a, "\n"); for (i = 1; i <= n; i++) l[a[i]] }
		$1 in l { split($1, b, ":"); rows[b[1] ":"] = rows[b[1] ":"] $0 "\n" }
		END { n = split(sessions, a, "\n"); for (i = 1; i <= n; i++) { split(a[i], b, "\t"); printf "%s%s\n", rows[b[1]], a[i] } }' |
	fzf --ansi --delimiter '\t' --with-nth 2.. --query "$3" --preview 'tmux capture-pane -ep -t {1}' --preview-window follow) || exit 0
[ -n "$2" ] && tmux send-keys -t "$2" q
tmux switch-client -c "$1" -Zt "${s%%	*}"
