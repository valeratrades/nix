#!/bin/sh
# statusLine command that draws nothing: the statusline's stdin is the one place Claude Code
# hands out the subscription's weekly utilisation. Read by service_arb/accounting's graf.
# A row is written only when the figure moves; sessions on an API key carry no rate_limits.
f="${XDG_STATE_HOME:-$HOME/.local/state}/claude/limits.tsv"
row=$(jq -r 'select(.rate_limits.seven_day) | [(now | floor), .rate_limits.seven_day.used_percentage] | @tsv')
[ -n "$row" ] || exit 0
mkdir -p "$(dirname "$f")"
[ "$(tail -n 1 "$f" 2>/dev/null | cut -f 2)" = "$(printf '%s' "$row" | cut -f 2)" ] || printf '%s\n' "$row" >>"$f"
