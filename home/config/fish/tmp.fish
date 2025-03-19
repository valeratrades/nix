# temporary scripts, can be cleaned at any moment, don't keep anything important here.

function load_page
	#! Load a single page, translate it, and save to a file.
	#! Usage: load_page PAGE [-n|--notify]
	#! PAGE: The page number to load
	#! -n, --notify: Enable notifications
	#! 
	#! Examples:
	#!   load_page 30
	#!   load_page 42 --notify
	#!   load_page 55 -n

	set page $argv[1]
	set notify false

	for arg in $argv[2..-1]
		switch $arg
		case '-n' '--notify'
			set notify true
		end
	end


	set base_path "$HOME/tmp/book_parser"
	mkdir -p "$base_path"
	set tmp_path "$base_path/page_$page.txt"
	set out_path "$base_path/page_"$page"_ti.txt"

	if ~/s/other/book_parser/target/debug/book_parser -c".page_text" --url "https://litmir.club/br/?b=801111&p=$page" -l"German" > $tmp_path
		if test "$notify" = true
			beep "loaded"
		end

		if cat $tmp_path | translate_infrequent -l"de" -k"4_000" > $out_path
			if test "$notify" = true
				beep "translated infrequent (to $out_path)"
			end
			return 0
		else
			if test "$notify" = true
				beep "translation failed"
			end
			return 1
		end
	else
		if test "$notify" = true
			beep "failed to load page"
		end
		return 1
	end
end

function load_pages
	#! Load a range of pages (start..end), where start is included and end is excluded.
	#! Usage: load_pages "START..END" [-n|--notify]
	#! START: First page to load (included)
	#! END: Last page number + 1 (excluded)
	#! -n, --notify: Enable notifications
	#!
	#! Examples:
	#!   load_pages "30..40"
	#!   load_pages "42..50" --notify
	#!   load_pages "55..60" -n

	set range (string split ".." $argv[1])
	set notify false

	for arg in $argv[2..-1]
		switch $arg
		case '-n' '--notify'
			set notify true
		end
	end

	set start $range[1]
	set end $range[2]

	for page in (seq $start (math "$end - 1"))
		echo "Loading page $page..."

		if not load_page $page (test "$notify" = true && echo "-n" || echo "")
			echo "Failed on page $page, stopping."
			return 1
		end
	end

	echo "Successfully loaded all pages from $start to "(math "$end - 1")
	return 0
end
