LOG="${XDG_STATE_HOME:-$HOME/.local/state}/nvim/lsp.log"
TRIM_ABOVE=157286400
KEEP=104857600

[ -f "$LOG" ] || exit 0
[ "$(stat -c %s "$LOG")" -gt "$TRIM_ABOVE" ] || exit 0

tmp="$(mktemp "$LOG.trim.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
tail -c "$KEEP" "$LOG" >"$tmp"

copied="$(stat -c %s "$tmp")"
[ "$copied" -eq "$KEEP" ] || {
	echo "refusing to trim: copied $copied of $KEEP bytes" >&2
	exit 1
}

# running nvims hold this file open and append to it, so the inode has to survive the trim
cat "$tmp" >"$LOG"
