#!/bin/sh
# kache hit rate over the last hour, from the tail of its own event log: a read of page-cached bytes, no daemon call.
# `kache stats` would spawn a daemon and walk the index, which is what this bar must not cost.
# Toolchains: entries used in the last hour, read-only from the index; two nightlies split every dependency's key.
log="$HOME/.cache/kache/events.jsonl"
since=$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%S)
toolchains=$(sqlite3 -readonly "file:$HOME/.cache/kache/index.db?mode=ro" \
	"select group_concat(v, ', ') from (select distinct rustc_version v from entries where last_accessed > datetime('now', '-1 hour') and rustc_version != '')")
tail -c 16000000 "$log" | awk -v since="$since" -v tc="$toolchains" '
	match($0, /"ts":"[^"]*"/) { ts = substr($0, RSTART + 6, 19) }
	ts < since { next }
	/"result":"local_hit"/ { h++ }
	/"result":"(miss|dup)"/ { m++ }
	END {
		n = h + m
		k = tc == "" ? 0 : split(tc, _, ", ")
		printf "{\"n\": %d, \"hit\": %d, \"toolchains\": %d, \"toolchain_list\": \"%s\"}\n", n, n ? 100 * h / n : 0, k, tc
	}
'
