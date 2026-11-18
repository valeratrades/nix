#!/bin/sh
# Device whose default route wins: lowest metric, NM's connectivity penalty included.
dev=$(ip -4 route show default | awk '{for (i = 1; i < NF; i++) { if ($i == "dev") d = $(i + 1); if ($i == "metric") m = $(i + 1) } if (best == "" || m + 0 < best) { best = m + 0; out = d } } END { print out }')
case "$dev" in
enp5s0) echo "󰈀 eth" ;;
enp6s0f3u*) echo "󰄜 tether" ;;
wlp4s0) echo "󰖩 $(nmcli -g GENERAL.CONNECTION dev show wlp4s0)" ;;
*) echo "$dev" ;;
esac
