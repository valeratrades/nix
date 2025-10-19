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

function process_book --argument wlimit
	mkdir -p chapters_split chapters_de chapters_ti failed_book_parser failed_translate
	set file (fd -e txt | head -n1)

	# split into chapters
	awk -v outdir="chapters_split" '
	/^Глава [0-9]+/ {
	if (out) close(out)
	match($0, /[0-9]+/)
	out = sprintf("%s/chapter_%s.txt", outdir, substr($0, RSTART, RLENGTH))
	}
	{ if (out) print > out }
	' "$file"

	function run_book_parser --argument ch num
		set de chapters_de/chapter_$num.txt
		if not book_parser -l German -f $ch > $de
			echo $num > failed_book_parser/chapter_$num.fail
		end
	end

	function run_translate --argument num wlimit
		set de chapters_de/chapter_$num.txt
		set ti chapters_ti/chapter_$num.txt
		if not cat $de | translate_infrequent -l de -w $wlimit > $ti
			echo $num > failed_translate/chapter_$num.fail
		end
	end

	for ch in (ls chapters_split/chapter_*.txt | sort -V)
		set base (basename $ch)
		set num (string replace -r 'chapter_([0-9]+)\.txt' '$1' $base)
		mkdir -p chapters_de
		run_book_parser $ch $num &
		while test (count (jobs -p)) -ge 2
			sleep 0.5
		end
	end
	wait

	for de in (ls chapters_de/chapter_*.txt | sort -V)
		set base (basename $de)
		set num (string replace -r 'chapter_([0-9]+)\.txt' '$1' $base)
		mkdir -p chapters_ti
		run_translate $num $wlimit &
		while test (count (jobs -p)) -ge 2
			sleep 0.5
		end
	end
	wait

	for fail in (ls failed_book_parser/*.fail ^/dev/null)
		set num (cat $fail)
		rm -f chapters_de/chapter_$num.txt chapters_ti/chapter_$num.txt
		set ch chapters_split/chapter_$num.txt
		run_book_parser $ch $num &
		while test (count (jobs -p)) -ge 2
			sleep 0.5
		end
	end
	wait

	for fail in (ls failed_translate/*.fail ^/dev/null)
		set num (cat $fail)
		rm -f chapters_ti/chapter_$num.txt
		run_translate $num $wlimit &
		while test (count (jobs -p)) -ge 2
			sleep 0.5
		end
	end
	wait

	cat (fd -e txt chapters_ti | sort -V) > out.txt
end
