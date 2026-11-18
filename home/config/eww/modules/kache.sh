#!/bin/sh
# kache hit rate over the last hour, from the tail of its own event log: a read of page-cached bytes, no daemon call.
# `kache stats` would spawn a daemon and walk the index, which is what this bar must not cost.
log="$HOME/.cache/kache/events.jsonl"
since=$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%S)
tail -c 16000000 "$log" | awk -v since="$since" '
	match($0, /"ts":"[^"]*"/) { ts = substr($0, RSTART + 6, 19) }
	ts < since { next }
	/"result":"local_hit"/ { h++ }
	/"result":"(miss|dup)"/ { m++ }
	END { n = h + m; printf "{\"n\": %d, \"hit\": %d}\n", n, n ? 100 * h / n : 0 }
'
