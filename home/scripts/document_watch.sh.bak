#TODO!!!!!: impplement correctly interactions with full filenames (with extensions) // currently can only guess
dw() {
	open_editor_after=0
	if [ "$1" = "-o" ] || [ "$1" = "--open" ]; then
		open_editor_after=1
		shift
	elif [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
		printf """compile document on change
  Usage:
    dw document_name

  The function will start piping compiled version into zathura, if the extension is known\n"""
		return 0
	fi
	name="$1"

	for ext in "typ" "tex" "md"; do
		if [ "${name}" = "*.${ext}" ]; then
			name="${name%.${ext}}"
			source_file="${name}"
			break
		elif [ -f "${name}.${ext}" ]; then
			source_file="${name}.${ext}"
			break
		fi
	done

	target="/tmp/${name}.pdf"
	notify-send $target $source_file

	if [ -f "${name}.typ" ]; then
		sudo killall typst
		typst compile $source_file $target # since `watch` is asyncronous, and without this line, at times zathura gets to the empty document before typst finishes compiling
		typst watch $source_file $target > /dev/null 2>&1 &

	elif [ -f "${name}.tex" ]; then
		printf "\033[31mTODO\n\033[0m"
	elif [ -f "${name}.md" ]; then
		printf "\033[31mTODO\n\033[0m"	
	else
		printf "\033[31mNo documents found with supported extensions and provided name\033[0m\n"
	fi

	zathura "$target" > /dev/null 2>&1 &

	if [ $open_editor_after -eq 1 ]; then
		$EDITOR "$source_file"
	fi
}

