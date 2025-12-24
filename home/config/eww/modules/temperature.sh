#!/bin/sh

# Read directly from hwmon sysfs to avoid poking broken legion_hwmon
get_temp_by_name() {
  for hwmon in /sys/class/hwmon/hwmon*; do
    if [ "$(cat "$hwmon/name" 2>/dev/null)" = "$1" ]; then
      val=$(cat "$hwmon/temp1_input" 2>/dev/null)
      echo $((val / 1000))
      return
    fi
  done
  echo 0
}

cpu_temp=$(get_temp_by_name "k10temp")
gpu_temp=$(get_temp_by_name "amdgpu")

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

printf '{"cpu": %d, "gpu": %d, "icon": "%s"}\n' "$cpu_temp" "$gpu_temp" "$icon"
