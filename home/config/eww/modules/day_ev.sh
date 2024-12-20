#!/usr/bin/env sh
# uninit: placeholder, class error
# outdated: day_ev, class warn
# default: day_ev, class info

MAX_WITHOUT_UPDATE=1
DEFAULT_CONTENT="_"

if day_ev=$(todo manual print-ev); then
	#notify-send "$day_ev" "// in eww's day_ev.sh" // gets called somehow. 1) What. Where is my display then?
	content="$day_ev"
	if last_update=$(todo manual last-ev-update-hours); then
		if [ "$MAX_WITHOUT_UPDATE" -le "$last_update" ]; then
			class="warn"
		else
			class="info"
		fi
	else
		content="panicked"
		class="error"
	fi
else
	content="$DEFAULT_CONTENT"
	class="warn"
fi


healthcheck_status_file="$(todo milestones healthcheck | head -n 1)"
if [ "$(find "$healthcheck_status_file" -mmin +120)" ]; then
	todo milestones healthcheck
	wait $!
fi
if [ -f "$healthcheck_status_file" ]; then
	status=$(cat "$healthcheck_status_file")
	if [ "$status" != "OK" ]; then
		class="error"
	fi
else
	content="$healthcheck_status_file does not exist"
	class="error"
fi



echo "{\"content\": \"${content}\", \"class\": \"$class\"}"
