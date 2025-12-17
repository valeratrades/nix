#!/bin/sh

temps=$(
  sensors 2>/dev/null | awk '
    /Tctl:/ {v=$2; gsub(/[+°C]/,"",v); cpu=int(v+0.5)}
    /edge:/ {v=$2; gsub(/[+°C]/,"",v); gpu=int(v+0.5)}
    END {
      if (cpu == "") cpu = 0
      if (gpu == "") gpu = 0
      print cpu, gpu
    }
  '
)

cpu_temp=$(echo "$temps" | cut -d' ' -f1)
gpu_temp=$(echo "$temps" | cut -d' ' -f2)

max_temp=$cpu_temp
[ "$gpu_temp" -gt "$max_temp" ] 2>/dev/null && max_temp=$gpu_temp

if [ "$max_temp" -lt 30 ]; then
	icon=""
elif [ "$max_temp" -lt 45 ]; then
	icon=""
elif [ "$max_temp" -lt 60 ]; then
	icon=""
elif [ "$max_temp" -lt 70 ]; then
	icon=""
else
	icon=""
fi

printf '{"content": "%s,%s", "icon": "%s"}\n' "$cpu_temp" "$gpu_temp" "$icon"
