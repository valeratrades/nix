#!/bin/sh

#TODO!!!!!!!!: fix the bug, where it it blows your ears off when another sound is ongoing when the beep with -l option happens.
# Should be fine if I just implement a global limit on volume, conditional on headphones. But currently fuck the sound-maxing feature.
beep() {	
	if [ $# = 1 ]; then
		if [ "$1" = "-l" ] || [ "$1" = "--loud" ]; then
			mute=$(pamixer --get-mute)
			if [ "$mute" = "true" ]; then
				pamixer --unmute
			fi

			volume=$(pamixer --get-volume)
			#pamixer --set-volume 100
			#mpv ${HOME}/Sounds/Notification.mp3 > /dev/null 2>&1
			#pamixer --set-volume $volume

			if [ "$mute" = "true" ]; then
				pamixer --mute
			fi

			notify-send "beep" -t 600000 # 10min
			return 0
		else
			printf "Only takes \"-l\"/\"--loud\". Provided: $1\n"
			return 1
		fi
	else # normal beep
		notify-send "beep"
		mpv ${HOME}/Sounds/Notification.mp3 > /dev/null 2>&1
		return 0
	fi
}	
