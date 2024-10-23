harpoon_config_path=${HOME}/s/help_scripts/shell_harpoon/config.sh

mute() {
	nohup alacritty -e nvim ${HOME}/s/help_scripts/shell_harpoon/config.sh -c "nnoremap q :q<CR>" -c "nnoremap <esc> :q<CR>" -c "autocmd QuitPre * :w" > /dev/null 2>&1 &
	sleep 0.35
	swaymsg floating enable

	wait $!
	# . $harpoon_config_path
	# swaymsg "for_window [app_id="Alacritty"]
}
,ui() {
	mute > /dev/null 2>&1
}


temp_file="${HOME}/tmp/shell_harpoon.sh"
,set() {
	dir=$(pwd)
	if [ -n "$1" ]; then
		dir="${dir}/$1"
	fi
	mkdir -p $(dirname "$temp_file")
	echo "export SHELL_HARPOON_CURRENT_DIR_DUMP=$(pwd)" > "$temp_file"
	. $temp_file
}

# # open nvim and cache the dir
# Reliance on existence of `e` command for opening the said editor.
,e() {
	,add "$@"
	e "$@"
}
e,() {
	_current_dir=$(pwd)
	,c
	e . "$@"
	cd "$_current_dir"
}
#

,c() {
	if [ -z $SHELL_HARPOON_CURRENT_DIR_DUMP ]; then
		printf "Error: first dump the current dir by doing \033[34m,add\033[0m\n"
		return 1
	else
		. $temp_file
		if type "cs" &>/dev/null; then
			cs $SHELL_HARPOON_CURRENT_DIR_DUMP
		else
			cd $SHELL_HARPOON_CURRENT_DIR_DUMP
		fi
	fi
}

. $harpoon_config_path
if [ -e "$temp_file" ]; then
	. $temp_file
fi	
# Does not work for the life of me. So doing the dumb way.
# config_functions=("${(@f)$(awk '/\(\) {/ {gsub(/\(\)/, "", $1); print $1}' $harpoon_config_path)}")
# for func in "${config_functions[@]}"; do
# 	eval "$func(){(source '$harpoon_config_path'; '$func')}"
# done

alias ,s="source $harpoon_config_path && _s"
alias ,r="source $harpoon_config_path && _r"
alias ,n="source $harpoon_config_path && _n"
alias ,t="source $harpoon_config_path && _t"
