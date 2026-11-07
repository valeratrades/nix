#!/usr/bin/env bash
# Prints the unread GitHub notification count. Issue/PR threads whose activity since our last read is all by `ours` get marked done.
set -uo pipefail

ours='["valeratrades","github-actions[bot]"]'
state="${XDG_STATE_HOME:-$HOME/.local/state}/eww/github_watermark"

notifications=$(timeout 10 gh api notifications 2>/dev/null) || { echo ""; exit 0; }
watermark=""
[ -f "$state" ] && watermark=$(cat "$state")

# $1: subject api url; $2: last_read_at, empty if never read. Prints true/false.
only_ours() {
	local commits='{}'
	if [[ $1 == */pulls/* ]]; then # timeline `committed` events carry only git authors, not logins
		commits=$(timeout 20 gh api --paginate "$1/commits" | jq -s 'add | map({key: .sha, value: .author.login}) | from_entries') || return 1
	fi
	timeout 20 gh api --paginate "${1/\/pulls\//\/issues\/}/timeline" | jq -s --arg since "$2" --argjson ours "$ours" --argjson commits "$commits" '
		[add[]
			| if .event == "line-commented" or .event == "commit-commented" then .comments[] | {a: .user.login, t: .created_at}
			elif .event == "committed" then {a: $commits[.sha], t: .author.date}
			else {a: (.actor.login // .user.login), t: (.created_at // .submitted_at)} end
			| select(.t > $since)]
		| length > 0 and all(.a as $a | $ours | index($a))' # empty: whatever triggered it is not in the timeline, so keep
}

removed=0
complete=1
while IFS=$'\t' read -r id url last_read; do
	verdict=$(only_ours "$url" "$last_read") || { complete=0; continue; }
	[ "$verdict" = true ] || continue
	if gh api -X DELETE "notifications/threads/$id" >/dev/null; then
		removed=$((removed + 1))
	else
		complete=0
	fi
done < <(jq -r --arg w "$watermark" '.[]
	| select(.updated_at > $w and (.subject.type == "Issue" or .subject.type == "PullRequest"))
	| [.id, .subject.url, (.last_read_at // "")] | @tsv' <<<"$notifications")

if [ "$complete" = 1 ] && [ "$(jq length <<<"$notifications")" -gt 0 ]; then # a failed check gets retried next poll
	mkdir -p "$(dirname "$state")"
	jq -r 'map(.updated_at) | max' <<<"$notifications" >"$state"
fi

echo $(($(jq length <<<"$notifications") - removed))
