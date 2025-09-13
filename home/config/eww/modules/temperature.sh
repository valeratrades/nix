#!/bin/sh

temperature=$(
  sensors 2>/dev/null | awk '
    /Tctl:/ {v=$2; gsub(/[+°C]/,"",v); printf "%.0f\n", v; exit}
    /Tdie:/ {v=$2; gsub(/[+°C]/,"",v); printf "%.0f\n", v; exit}
    /edge:/ {v=$2; gsub(/[+°C]/,"",v); printf "%.0f\n", v; exit}
    /CPU:/  {v=$2; gsub(/[+°C]/,"",v); printf "%.0f\n", v; exit}
  '
)

[ -z "$temperature" ] && temperature=0

if [ "$temperature" -lt 30 ]; then
	icon=""
elif [ "$temperature" -lt 45 ]; then
	icon=""
elif [ "$temperature" -lt 60 ]; then
	icon=""
elif [ "$temperature" -lt 70 ]; then
	icon=""
else
	icon=""
fi

printf '{"content": "%s", "icon": "%s"}\n' "$temperature" "$icon"
