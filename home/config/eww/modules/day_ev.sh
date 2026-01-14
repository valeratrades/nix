#!/usr/bin/env sh
# uninit: placeholder, class error
# outdated: day_ev, class warn
# default: day_ev, class info

MAX_WITHOUT_UPDATE=1
DEFAULT_CONTENT="_"

if day_ev=$(todo manual print-ev); then
	content="$day_ev"
	if last_update=$(todo manual last-ev-update-hours 2>&1); then
		if [ "$MAX_WITHOUT_UPDATE" -le "$last_update" ]; then
			class="warn"
		else
			class="info"
		fi
	else
		content=$(printf "%.35s" "${last_update#Error: }")
		class="error"
	fi
else
	content="$DEFAULT_CONTENT"
	class="warn"
fi

temp_var_file="/run/user/$(id -u)/todo_milestones_healthcheck_status_path"
success=0
if [ -f "$temp_var_file" ]; then
	healthcheck_status_file="$(cat "$temp_var_file")"
	if [ "$healthcheck_status_file" != "" ]; then
		success=1
	fi
fi
if [ "$success" != 1 ]; then
	healthcheck_status_file="$(todo milestones healthcheck | head -n 1)"
	echo "$healthcheck_status_file" > "$temp_var_file"
fi

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
