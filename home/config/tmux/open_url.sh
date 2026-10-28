#!/bin/sh
# `$1`: line; `$2`: x (0-based). Exits 1 when no URL is under x
url=$(printf '%s\n' "$1" | awk -v x="$(($2 + 1))" '{
	off = 0; s = $0
	while (match(s, /https?:\/\/[^ \t"<>()`'"'"'│]+/)) {
		a = off + RSTART; b = a + RLENGTH
		if (x >= a && x < b) { u = substr(s, RSTART, RLENGTH); sub(/[.,;:!?]+$/, "", u); print u; exit }
		off += RSTART + RLENGTH - 1; s = substr(s, RSTART + RLENGTH)
	}
}')
[ -n "$url" ] || exit 1
xdg-open "$url" >/dev/null 2>&1
