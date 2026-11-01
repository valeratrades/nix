#!/bin/sh
# statusLine command that draws nothing: the statusline's stdin is the one place Claude Code
# hands out the subscription's utilisation, fed by every API response's headers.
# limits.tsv (weekly history) and sessions.tsv (the window each session is paid from) are read by
# service_arb/accounting's graf; rate_limits.json (latest snapshot) by tmux/claude_sessions.rs.
# Sessions on an API key carry no rate_limits.
d="${XDG_STATE_HOME:-$HOME/.local/state}/claude"
f="$d/limits.tsv"
input=$(cat)
limits=$(printf '%s' "$input" | jq -c '.rate_limits // empty')
[ -n "$limits" ] || exit 0
mkdir -p "$d"
# Every session writes here, idle ones with figures older than a busy neighbour's; usage within
# a window only grows, so a later window wins and the same window keeps its max.
old=$(cat "$d/rate_limits.json" 2>/dev/null || echo '{}')
tmp=$(mktemp "$d/rate_limits.XXXXXX")
jq -cn --argjson old "$old" --argjson new "$limits" '
  reduce ($new | keys[]) as $k ($old;
    .[$k] as $o | $new[$k] as $n
    | .[$k] = if $o == null or $n.resets_at > $o.resets_at then $n
              elif $n.resets_at == $o.resets_at and $n.used_percentage > $o.used_percentage then $n
              else $o end)' >"$tmp" && mv "$tmp" "$d/rate_limits.json"
# rate_limits.json mixes accounts once sessions run on more than one, so the history is kept off
# this session's own figures: a seven-day window is told by when it resets, and a row is a new high of one.
set -- $(printf '%s' "$limits" | jq -r '.seven_day // empty | "\(.used_percentage) \(.resets_at)"')
[ $# -eq 2 ] || exit 0
touch "$f" "$d/sessions.tsv"
awk -F '\t' -v used="$1" -v resets="$2" '$3 == resets && $2 + 0 >= used + 0 { seen = 1 } END { exit seen }' "$f" &&
  printf '%s\t%s\t%s\n' "$(date +%s)" "$1" "$2" >>"$f"
session=$(printf '%s' "$input" | jq -er .session_id) || exit 1
[ "$(awk -F '\t' -v s="$session" '$2 == s { r = $3 } END { print r }' "$d/sessions.tsv")" = "$2" ] ||
  printf '%s\t%s\t%s\n' "$(date +%s)" "$session" "$2" >>"$d/sessions.tsv"
