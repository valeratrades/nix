#!/bin/sh

length=$(pgrep "openvpn" | wc -l)
if [ $length -gt 2 ]; then
	echo "1"
else
	echo "0"
fi
