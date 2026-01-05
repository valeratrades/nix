# nvim shortcut, that does cd first, to allow for harpoon to detect project directory correctly
# e stands for editor
#NB: $1 nvim arg has to be the path
function e
	set -l nvim_commands ""
	if test "$argv[1]" = "--flag_load_session"
		set nvim_commands "-c SessionLoad"
		set argv $argv[2..-1]
	end

	set -l nvim_evocation "nvim"
	if test "$argv[1]" = "--use_sudo_env"
		set nvim_evocation "sudo -Es -- nvim"
		set argv $argv[2..-1]
	end

	#git_push_after="false"
	# if [ "$1" = "--git_sync" ]; then
	#	git_push_after="true"
	#	shift
	#	git -C "$1" pull > /dev/null 2>&1
	#fi

	set -l full_command "$nvim_evocation ."
	if test -n "$argv[1]"
		if test -d "$argv[1]"
			pushd "$argv[1]" > /dev/null
			set argv $argv[2..-1]
			set full_command "$nvim_evocation $argv ."
		else
			set -l could_fix 0
			set -l try_extensions "" .sh .rs .go .py .fish .json .txt .md .typ .tex .html .js .toml .conf .cs .cpp .yaml .yml .xml .ini .env .log
			# note that indexing starts at 1, as we're in a piece of shit zsh.
			for ext in $try_extensions
				set -l try_path "$argv[1]$ext"
				if test -f "$try_path"
					pushd (dirname "$try_path") > /dev/null
					set argv $argv[2..-1]
					set full_command "$nvim_evocation (basename "$try_path") $argv $nvim_commands"
					eval $full_command
					popd > /dev/null
					# if git_push_after; then
					#	push ${1}
					#fi
					return 0
				end
			end
			set full_command "$nvim_evocation $argv"
		end
	end

	set full_command "$full_command $nvim_commands"
	eval $full_command

	# clean the whole dir jump stack. (sounds dangerous, but so far nothing seems affected)
	while popd >/dev/null 2>&1
	end

	# if [ "$git_push_after" = "true" ]; then
	#	push ${1}
	#fi
end

function ep
	e --flag_load_session $argv
end
function se
	e --use_sudo_env $argv
end
function et
   set ext "md"
   if [ ! -z "$argv[1]" ]
       set ext $argv[1]
   end
   
   nvim /tmp/a_temporary_note.$ext -c 'nnoremap q gg^vG^g_"+y:qa!<CR>' -c 'startinsert'
end

alias ec="e $NIXOS_CONFIG/home/config/nvim"
alias es="nvim $NIXOS_CONFIG/home/config/fish/main.fish"
alias epy="e ~/envs/Python/lib/python3.11/site-packages"


# to simplify pasting stuff
alias nano="nvim"
complete -c nano -w nvim
alias vi="nvim"
complete -c vi -w nvim
alias vim="nvim"
complete -c vim -w nvim
