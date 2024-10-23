#!/bin/sh

# doesn't work with hours, and that's intentional - starting a >1h timer with this is prone to failure, as it does not persist state between shutdowns.
timer() {
	trap 'eww update timer="";return 1' INT
	trap 'eww update timer=""' EXIT
	no_beep="false"
	if [ "$1" = "-q" ]; then
		no_beep="true"
		shift
	fi
	if [ "$2" = "-q" ]; then
		no_beep="true"
	fi

	if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
		printf """\
Usage: timer [time] [-q]

Arguments:
	time: time in seconds or in format \"mm:ss\".
	-q: quiet mode, shows forever notif instead of beeping.
"""
		return 0
	fi


	input=$1
	if [[ "$input" == *":"* ]]; then
		IFS=: read mins secs <<< "$input"
		left=$((mins * 60 + secs))
	else
		left=$input
	fi

	while [ $left -gt 0 ]; do
		mins=$((left / 60))
		secs=$((left % 60))
		formatted_secs=$(printf "%02d" $secs)
		eww update timer="${mins}:${formatted_secs}"
		sleep 1
		left=$((left - 1))
	done	
	eww update timer=""


	if [ "$no_beep" = "false" ]; then
		beep --loud
	else
		notify-send "timer finished" -t 2147483647
		return 0
	fi
}
