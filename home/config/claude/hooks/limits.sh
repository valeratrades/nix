#!/bin/sh
# statusLine command that draws nothing: the statusline's stdin is the one place Claude Code
# hands out the subscription's utilisation, fed by every API response's headers.
# limits.tsv (weekly history) is read by service_arb/accounting's graf; rate_limits.json
# (latest snapshot) by tmux/claude_sessions.rs. Sessions on an API key carry no rate_limits.
d="${XDG_STATE_HOME:-$HOME/.local/state}/claude"
f="$d/limits.tsv"
limits=$(jq -c '.rate_limits // empty')
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
row=$(jq -r 'select(.seven_day) | [(now | floor), .seven_day.used_percentage, .seven_day.resets_at] | @tsv' "$d/rate_limits.json")
[ -n "$row" ] || exit 0
[ "$(tail -n 1 "$f" 2>/dev/null | cut -f 2-)" = "$(printf '%s' "$row" | cut -f 2-)" ] || printf '%s\n' "$row" >>"$f"
