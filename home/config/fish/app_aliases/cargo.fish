alias caclip="cargo clippy --tests -- -Dclippy::all"
alias ctn="cargo test -- --nocapture"
alias cpad="cargo publish --allow-dirty"
alias cflags="RUST_LOG='debug,hyper=info' RUST_BACKTRACE=1 RUST_LIB_BACKTRACE=0"
alias cscript="cargo +nightly -Zscript" # https://doc.rust-lang.org/cargo/reference/unstable.html#script
#!/usr/bin/env -S cargo +nightly -Zscript

# cargo build install
function cbi
	set guess_name (basename (pwd))
	if test -n "$argv[1]"
		if test "$argv[1]" = "-d" -o "$argv[1]" = "--dev"
			set path_to_build "target/debug/$guess_name"
			cargo build --profile dev
		else
			return 1
		end
	else
		set path_to_build "target/release/$guess_name"
		cargo build --release
	end

	if test -f "./$path_to_build"
		sudo cp -f "./$path_to_build" /usr/local/bin/
	else if test -f "../$path_to_build"
		sudo cp -f "../$path_to_build" /usr/local/bin/
	else
		printf "Could not guess the built binary location\n"
		return 1
	end
end

# for some reason truncates the output of `cargo test`
function cq
	set cmd "$argv"
	set cargo_output (script -f -q /dev/null -c="cargo --quiet $cmd")
	echo "$cargo_output" | awk '
	BEGIN{
	RS="\r\n\r\n";
	}
	{
	print_line = 1
	first_word = $1
	if (index(first_word, "[33mwarning\033") > 0) {
	if (index($0, "Nextest") == 0) {
	print_line = 0
	}
	}
	if (print_line == 1) {
	print $0
	}
	}'
end

function cpublish
	cargo release --no-confirm --execute "$argv"
end

# Pause resource-hungry apps
function pause_greedy
	set greedy "discord telegram"

	function cleanup
		for pid in $paused_pids
			if test -e /proc/$pid
				kill -CONT $pid
			end
		end
		exit 1
	end

	set paused_pids ""
	for app in $greedy
		set app_pids (ps aux | awk -v app="$app" '$0 ~ app {print $2}')
		for pid in $app_pids
			set state (ps -o state= -p $pid)
			if test "$state" != "T"
				set paused_pids "$paused_pids $pid"
				kill -STOP $pid
			end
		end
	end
	trap cleanup INT
	trap cleanup EXIT
end

function stop_all_run_cargo
	pause_greedy > /dev/null 2>&1
	cargo $argv
end

function c
	cargo $argv
end

function rd
    set base_name (basename (pwd))
    ./target/debug/$base_name $argv
end

function rr
    set base_name (basename (pwd))
    ./target/release/$base_name $argv
end


function cw
	cargo watch --todo manual counter-step --cargo-watch >/dev/null 2>&1 &
	set pid1 $last_pid

	function cleanup
		kill $pid1 2>/dev/null
		wait $pid1 2>/dev/null
		trap - INT
	end

	trap cleanup INT
	cargo watch -c -x "b"
	cleanup
end

alias cu="cargo clean && cargo update"

function ct
	function cleanup
		eww update cargo_compiling=false
	end

	trap cleanup EXIT
	trap cleanup INT

	set starttime (date +%s)
	set run_after "false"
	eww update cargo_compiling=true

	if test "$argv" = ""
		ct r
	else if test "$argv[1]" = "r"
		stop_all_run_cargo lbuild $argv[2..-1]
		set run_after "true"
	else if test "$argv[1]" = "b"
		cargo build --release $argv[2..-1]
	else if test "$argv[1]" = "c"
		stop_all_run_cargo lcheck $argv[2..-1]
	else
		printf "Only takes \"c\", \"r\" or \"b\". Provided: $argv[1]\n"
		return 1
	end

	set endtime (date +%s)
	set elapsedtime (math $endtime - $starttime)
	if test $elapsedtime -gt 20
		beep
		notify-send "cargo compiled"
	end

	if test "$run_after" = "true"
		cargo run $argv
	end
end

#DEPENDS: [cq]
function ce
	set cmd "cq \"nextest run"
	for arg in $argv
		set cmd "$cmd -E 'test(/$arg/)'"
	end
	set cmd "$cmd\""
	echo $cmd

	set result (eval $cmd)
	printf (string trim $result)
end
