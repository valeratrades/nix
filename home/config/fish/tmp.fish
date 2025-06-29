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
	set book_path "$base_path/пкк_1"
	mkdir -p "$book_path/src"
	set tmp_path "$book_path/src/page_$page.txt"
	set vocabulary "6_000"
	set out_path "$book_path/page_"$page".de.ti$vocabulary.md"

	if ~/s/other/book_parser/target/debug/book_parser -c "#main" -c ".BookText" -c".col-12 > section:nth-child(3)" -c".col-12 > section:nth-child(4)" --url "https://flibusta.is/b/699753/read#t$page" -l"German" > $tmp_path
	#if ~/s/other/book_parser/target/debug/book_parser -c".col-12 > section:nth-child(3)" -c".col-12 > section:nth-child(4)" --url "https://litmir.club/br/?b=801111&p=$page" -l"German" > $tmp_path
		if test "$notify" = true
			beep "loaded"
		end

		if cat $tmp_path | translate_infrequent -l"de" -k"$vocabulary" > $out_path
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
    #! Load a range of pages in Rust-like syntax: start..end (exclusive) or start..=end (inclusive).
    #! Usage: load_pages "START..END" [-n|--notify] or load_pages "START..=END" [-n|--notify]
    #! START: First page to load (included)
    #! END: Last page (excluded in START..END, included in START..=END)
    #! -n, --notify: Enable notifications
    #!
    #! Examples:
    #!   load_pages "30..=40"
    #!   load_pages "42..50" --notify
    #!   load_pages "55..=60" -n
    set notify false
    for arg in $argv[2..-1]
        switch $arg
        case '-n' '--notify'
            set notify true
        end
    end
    
    # Check for inclusive range (..=)
    if string match -q "*..=*" $argv[1]
        set range (string split "..=" $argv[1])
        set start $range[1]
        set end $range[2]
        set last_page $end
    else
        # Regular exclusive range (..)
        set range (string split ".." $argv[1])
        set start $range[1]
        set end $range[2]
        set last_page (math "$end - 1")
    end
    
    for page in (seq $start $last_page)
        echo "Loading page $page..."
        if not load_page $page (test "$notify" = true && echo "-n" || echo "")
            echo "Failed on page $page, stopping."
            return 1
        end
    end
    
    echo "Successfully loaded all pages from $start to $last_page"
    return 0
end
