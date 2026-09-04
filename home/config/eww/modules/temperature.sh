#!/bin/sh

# Read directly from hwmon sysfs to avoid poking broken legion_hwmon.
# `read` rather than $(cat ...): at a 5s poll the scan is ~15 files, and a fork per file was
# 90% of this script's cost. Sets temp_reply instead of echoing so the caller needs no subshell.
temp_by_name() {
  for hwmon in /sys/class/hwmon/hwmon*; do
    read -r name < "$hwmon/name" 2>/dev/null || continue
    [ "$name" = "$1" ] || continue
    read -r val < "$hwmon/temp1_input" 2>/dev/null || break
    temp_reply=$((val / 1000))
    return
  done
  temp_reply=0
}

temp_by_name k10temp; cpu_temp=$temp_reply
temp_by_name amdgpu;  gpu_temp=$temp_reply

# The dGPU has no hwmon, so it was absent from this bar entirely — the one number that went
# unwatched while it was the part that ran hottest under PRIME sync. -1 means runtime-suspended;
# asking anyway would wake it and keep it awake.
#
# NB: with services/graphics.nix pinning powerManagement.finegrained = false the card sits at
# `active` permanently, so this branch is always taken and nvidia-smi (~0.02s) is now the bulk
# of this script. It stays because the reading is the point; -1 is for a host that does suspend.
dgpu_temp=-1
for dev in /sys/bus/pci/drivers/nvidia/0000:*; do
  read -r status < "$dev/power/runtime_status" 2>/dev/null || continue
  if [ "$status" = active ] && command -v nvidia-smi >/dev/null 2>&1; then
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
