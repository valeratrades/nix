# TODO!!!!!: implement correctly interactions with full filenames (with extensions) // currently can only guess
function dw
	set open_editor_after 0
	if test "$argv[1]" = "-o" -o "$argv[1]" = "--open"
		set open_editor_after 1
		set argv $argv[2..-1]
	else if test "$argv[1]" = "-h" -o "$argv[1]" = "--help" -o "$argv[1]" = "help"
		printf """compile document on change
		Usage:
		dw document_name

		The function will start piping compiled version into zathura, if the extension is known\n"""
		return 0
	end
	set name "$argv[1]"

	for ext in "typ" "tex" "md"
		if test "$name" = "*.$ext"
			set name (string replace ".$ext" "" $name)
			set source_file "$name"
			break
		else if test -f "$name.$ext"
			set source_file "$name.$ext"
			break
		end
	end

	set target "/tmp/$name.pdf"
	notify-send $target $source_file

	if test -f "$name.typ"
		sudo killall typst
		typst compile $source_file $target # since `watch` is asynchronous, and without this line, zathura might get to the empty document before typst finishes compiling
		typst watch $source_file $target > /dev/null 2>&1 &
	else if test -f "$name.tex"
		printf "\033[31mTODO\n\033[0m"
	else if test -f "$name.md"
		printf "\033[31mTODO\n\033[0m"
	else
		printf "\033[31mNo documents found with supported extensions and provided name\033[0m\n"
	end

	zathura "$target" > /dev/null 2>&1 &

	if test $open_editor_after -eq 1
		$EDITOR "$source_file"
	end
end
