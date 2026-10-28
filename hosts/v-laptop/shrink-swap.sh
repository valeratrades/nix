#!/usr/bin/env bash
# Live: shrink swap (last partition) to <GiB>, freed space goes to /home right before it. Keeps every UUID, so hardware-configuration.nix stays valid.
# usage: shrink-swap.sh <GiB> [--apply]   (dry-run without --apply)
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"

disk=/dev/nvme0n1
home_part=${disk}p3
swap_part=${disk}p5
swap_uuid=4fc0e3da-5640-4939-a5e2-e19ad7419e46
swap_sectors=$((${1:?usage: shrink-swap.sh <GiB> [--apply]} * 1024 ** 3 / 512))
align=2048

part() { sfdisk -J "$disk" | jq -r ".partitiontable.partitions[] | select(.node == \"$1\") | .$2"; }
home_start=$(part "$home_part" start)
home_size=$(part "$home_part" size)
swap_start=$(part "$swap_part" start)
swap_end=$((swap_start + $(part "$swap_part" size)))

[ "$(blkid -s UUID -o value "$swap_part")" = "$swap_uuid" ] || { echo "$swap_part is not the swap from hardware-configuration.nix" >&2; exit 1; }
[ $((home_start + home_size)) = "$swap_start" ] || { echo "/home and swap are not adjacent" >&2; exit 1; }
[ "$(findmnt -no SOURCE /home)" = "$home_part" ] || { echo "/home is not on $home_part" >&2; exit 1; }

new_swap_start=$(((swap_end - swap_sectors) / align * align))
new_home_size=$((new_swap_start - home_start))
[ "$new_home_size" -gt "$home_size" ] || { echo "swap is already <= $1G" >&2; exit 1; }

swap_used_kb=$(awk '/SwapTotal/{t=$2} /SwapFree/{f=$2} END{print t-f}' /proc/meminfo)
mem_avail_kb=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
[ $((swap_used_kb * 2)) -lt "$mem_avail_kb" ] || { echo "not enough free RAM to swapoff (${swap_used_kb}K swapped, ${mem_avail_kb}K available)" >&2; exit 1; }

old_table=$(sfdisk -d "$disk")
new_table=$(echo "$old_table" | awk -v hp="$home_part" -v hs="$new_home_size" -v sp="$swap_part" -v ss="$new_swap_start" -v sz="$((swap_end - new_swap_start))" '
	$1 == hp { sub(/size= *[0-9]+/, "size=" hs) }
	$1 == sp { sub(/start= *[0-9]+/, "start=" ss); sub(/size= *[0-9]+/, "size=" sz) }
	{ print }')

[ "$(diff <(echo "$old_table") <(echo "$new_table") | grep -c '^>')" = 2 ] || { echo "new table touches more than /home and swap" >&2; exit 1; }
new_home_start=$(echo "$new_table" | awk -v hp="$home_part" '$1 == hp { match($0, /start= *[0-9]+/); s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); print s }')
[ "$new_home_start" = "$home_start" ] || { echo "/home start would move" >&2; exit 1; }

echo "/home: +$(((new_home_size - home_size) / 2 / 1024 / 1024))G, swap: $(((swap_end - new_swap_start) / 2 / 1024 / 1024))G"
diff <(echo "$old_table") <(echo "$new_table") || true # diff exits 1 when tables differ, which is the point
echo "$new_table" | sfdisk --no-act --wipe never --wipe-partitions never "$disk" >/dev/null

[ "${2:-}" = --apply ] || { echo "dry run ok; rerun with --apply"; exit 0; }

backup=/root/nvme0n1-$(date +%Y%m%d-%H%M%S).sfdisk
echo "$old_table" >"$backup"
echo "table backup: $backup"

swapoff "$swap_part"
trap 'echo "failed before resize2fs; fs untouched. to undo: sfdisk --no-reread --no-tell-kernel --wipe never --wipe-partitions never $disk < $backup && partx -u $disk && swapon $swap_part" >&2' ERR
echo "$new_table" | sfdisk --no-reread --no-tell-kernel --wipe never --wipe-partitions never "$disk"
partx -u --nr "${swap_part##*p}" "$disk" # swap first: kernel refuses to grow p3 while it overlaps the old swap
partx -u --nr "${home_part##*p}" "$disk" # BLKPG resize; kernel accepts it for mounted p3 since its start is unchanged
[ "$(blockdev --getsz "$home_part")" = "$new_home_size" ] || false # kernel did not pick up the new size; trips the ERR trap
trap - ERR
resize2fs "$home_part"
mkswap -U "$swap_uuid" "$swap_part"
udevadm settle
swapon --show=NAME --noheadings | grep -qx "$swap_part" || swapon "$swap_part" # systemd may already have activated it on the udev event
df -h /home
swapon --show
