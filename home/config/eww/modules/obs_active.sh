#!/bin/sh

length=$(pgrep "obs" | wc -l)
# no clue why it's 2, but it is
if [ $length -gt 2 ]; then
	echo "1"
else
	echo "0"
fi
