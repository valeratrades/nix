#!/bin/sh
# Phone on one of this laptop's USB-C ports (usb1-port1/2, see hosts/v-laptop/configuration.nix) but not tethering usefully.
# Empty text = nothing to say.
for dev in /sys/bus/usb/devices/1-1 /sys/bus/usb/devices/1-2; do
	[ -d "$dev" ] || continue
	read -r vendor < "$dev/idVendor"
	case "$vendor" in 2717 | 18d1) ;; *) continue ;; esac # Xiaomi in tether mode, Google ids in MTP/charging mode
	iface=$(ls "$dev"/*:*/net 2>/dev/null | head -n1)
	if [ -z "$iface" ]; then
		echo "tether off"
	elif [ -z "$(ip -4 -o addr show dev "$iface")" ]; then
		echo "tether: no lease"
	elif [ "$(nmcli -g GENERAL.IP4-CONNECTIVITY dev show "$iface")" != "4 (full)" ]; then
		echo "tether: no internet"
	fi
	exit 0
done
