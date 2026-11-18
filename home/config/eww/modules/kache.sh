#!/bin/sh
# kache hit rate over the last hour, from the tail of its own event log: a read of page-cached bytes, no daemon call.
# `kache stats` would spawn a daemon and walk the index, which is what this bar must not cost.
# Several kache versions: their key schemas differ, so nothing one stores is ever hit by the other.
# Toolchains: entries used in the last hour, read-only from the index; two nightlies split every dependency's key.
log="$HOME/.cache/kache/events.jsonl"
since=$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%S)
toolchains=$(sqlite3 -readonly "file:$HOME/.cache/kache/index.db?mode=ro" \
	"select group_concat(v, ', ') from (select distinct rustc_version v from entries where last_accessed > datetime('now', '-1 hour') and rustc_version != '')")
tail -c 16000000 "$log" | awk -v since="$since" -v tc="$toolchains" '
	match($0, /"ts":"[^"]*"/) { ts = substr($0, RSTART + 6, 19) }
	ts < since { next }
	match($0, /"version":"[^"]*"/) { kv[substr($0, RSTART + 11, RLENGTH - 12)] = 1 }
	/"result":"local_hit"/ { h++ }
	/"result":"(miss|dup)"/ { m++ }
	END {
		n = h + m
		k = tc == "" ? 0 : split(tc, _, ", ")
		nv = 0; vl = ""
		for (v in kv) { nv++; vl = vl (vl == "" ? "" : ", ") v }
		printf "{\"n\": %d, \"hit\": %d, \"toolchains\": %d, \"toolchain_list\": \"%s\", \"kache_versions\": %d, \"kache_version_list\": \"%s\"}\n", n, n ? 100 * h / n : 0, k, tc, nv, vl
	}
'
