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

# The dGPU has no hwmon, so it was absent from this bar entirely — the one number that went
# unwatched while it was the part that ran hottest under PRIME sync. -1 means runtime-suspended,
# which is its normal state under offload; asking anyway would wake it and keep it awake.
dgpu_temp=-1
for dev in /sys/bus/pci/drivers/nvidia/0000:*; do
  if [ "$(cat "$dev/power/runtime_status" 2>/dev/null)" = active ] && command -v nvidia-smi >/dev/null 2>&1; then
    dgpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo -1)
  fi
done

max_temp=$cpu_temp
[ "$gpu_temp" -gt "$max_temp" ] 2>/dev/null && max_temp=$gpu_temp
[ "$dgpu_temp" -gt "$max_temp" ] 2>/dev/null && max_temp=$dgpu_temp

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

printf '{"cpu": %d, "gpu": %d, "dgpu": %d, "icon": "%s"}\n' "$cpu_temp" "$gpu_temp" "$dgpu_temp" "$icon"
