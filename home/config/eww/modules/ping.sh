#!/usr/bin/env sh

HOST="8.8.8.8"

# Some networks are blocking pings, so in these cases have to settle for knowing there is some connection.
if ! ping=$(timeout 2 ping -c 1 -W 1 "$HOST" 2> /dev/null); then
	if timeout 2 nmcli -t -f DEVICE,STATE device 2>/dev/null | grep "^wlan0:connected$" > /dev/null; then
		echo "Some"
	else
		echo "None"
	fi
else
  rtt=$(echo "$ping" | sed -n 's/.*time=\([0-9]\+\).* ms/\1/p')

  [ -z "$rtt" ] && echo "" && exit 1
  echo "$rtt"
fi
