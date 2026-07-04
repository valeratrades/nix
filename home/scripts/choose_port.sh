#!/usr/bin/env sh

# Apparently can just specify `port = 0` when openning connection, to have system auto-assign it. So this is useless.

round=1
while [ $# -gt 0 ]; do
	case "$1" in
		-r|--round) round="$2"; shift 2 ;;
		*) echo "unknown arg: $1" >&2; exit 1 ;;
	esac
done

while true; do
	port=$(shuf -i 49152-65535 -n 1)
	port=$((port / round * round))

		# Check if the port is in use (suppressing stderr)
		if [ "$port" -ge 49152 ] && ! ss -tulwn | grep -q ":$port " 2>/dev/null; then
			echo "$port"
			break
		fi
done
