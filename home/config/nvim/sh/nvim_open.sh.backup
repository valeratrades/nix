#!/bin/sh

# nvim shortcut, that does cd first, to allow for harpoon to detect project directory correctly
# e stands for editor
#NB: $1 nvim arg has to be the path
e() {
	nvim_commands=""
	if [ "$1" = "--flag_load_session" ]; then
		nvim_commands="-c SessionLoad"
		shift
	fi
	nvim_evocation="nvim"
	if [ "$1" = "--use_sudo_env" ]; then
		nvim_evocation="sudo -Es -- nvim"
		shift
	fi
	#git_push_after="false"
	#if [ "$1" = "--git_sync" ]; then
	#	git_push_after="true"
	#	shift
	#	git -C "$1" pull > /dev/null 2>&1
	#fi
	local full_command="${nvim_evocation} ."
	if [ -n "$1" ]; then
		if [ -d "$1" ]; then
			pushd ${1} &> /dev/null
			shift
			full_command="${nvim_evocation} ${@} ."
		else
			local could_fix=0
			local try_extensions=("" ".sh" ".rs" ".go" ".py" ".json" ".txt" ".md" ".typ" ".tex" ".html" ".js" ".toml" ".conf")
			# note that indexing starts at 1, as we're in a piece of shit zsh.
			for i in {1..${#try_extensions[@]}}; do
				local try_path="${1}${try_extensions[$i]}"
				if [ -f "$try_path" ]; then
					pushd $(dirname $try_path) &> /dev/null
					shift
					full_command="${nvim_evocation} $(basename $try_path) ${@} ${nvim_commands}"
					eval ${full_command}
					popd &> /dev/null
					#if git_push_after; then
					#	push ${1}
					#fi
					return 0
				fi
			done
			full_command="${nvim_evocation} ${@}"
		fi
	fi

	full_command+=" ${nvim_commands}"
	eval ${full_command}

	# clean the whole dir stack, which would drop back if `pushd` was executed, and do nothing otherwise.
	# hopefuly I'm not breaking anything by doing so.
	while [ "$(dirs -v | wc -l)" -gt 1 ]; do popd; done > /dev/null 2>&1

	
	#if [ "$git_push_after" = "true" ]; then
	#	push ${1}
	#fi
}
e ${@}
