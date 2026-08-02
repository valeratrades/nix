# A rust-analyzer that panics during name resolution parks its main loop but keeps the
# lspmux socket open, so every attached editor and agent goes on reporting the server as
# connected while no request is ever answered again. lspmux writes the panic to the journal
# and tells nobody; this is what turns that into something a human sees.

notified=""
journalctl --user --unit lspmux --follow --lines 0 --output cat |
	sed --unbuffered 's/\x1b\[[0-9;]*m//g' | # lspmux colours its log even into the journal
	grep --line-buffered -F 'panicked at' |
	while read -r line; do
		pid="${line##*instance\{pid=}"
		pid="${pid%%\}*}"
		case "$pid" in
		'' | *[!0-9]*) continue ;;
		esac
		if [ "$pid" = "$notified" ]; then continue; fi
		notified="$pid"

		# the instance can already be reaped by the time we look; the panic is worth
		# reporting either way, so a missing workspace must not swallow the notification
		root="$(lspmux status --json |
			jq -r --argjson pid "$pid" '.instances[] | select(.pid == $pid) | .workspaceRoot')" ||
			root=""

		notify-send --urgency critical --app-name lspmux \
			"rust-analyzer panicked (pid $pid)" \
			"${root:-workspace unknown}

Editors will keep showing it connected. Recover with:
systemctl --user restart lspmux"
	done
