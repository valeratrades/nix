set __fish_scripts_dir (status dirname)
source $__fish_scripts_dir/videos.fish
source $__fish_scripts_dir/server.fish
source $__fish_scripts_dir/weird/__main__.fish
source $__fish_scripts_dir/document_watch.fish

function beep
	$__fish_scripts_dir/beep.rs $__fish_scripts_dir/assets/sound/Notification.mp3 $argv
end

function 2fa; $__fish_scripts_dir/2fa.rs $argv; end
function timer; $__fish_scripts_dir/timer.rs $argv; end
function theme; $__fish_scripts_dir/theme_toggle.rs $argv; end
function mvd; $__fish_scripts_dir/mvd.rs $argv; end
function calendar; $__fish_scripts_dir/calendar.rs $argv; end
function cargo_clean; $__fish_scripts_dir/cargo_clean.rs $argv; end
function translate_book; $__fish_scripts_dir/translate_book.rs $argv; end
function clipboard_to_keystrokes; $__fish_scripts_dir/clipboard_to_keystrokes.rs $argv; end
function eww_open_on; $__fish_scripts_dir/eww_open_on.rs $argv; end
function bluetooth; $__fish_scripts_dir/bluetooth.rs $argv; end
function cnix_release; $__fish_scripts_dir/cnix_release.rs $argv; end
function nb; $__fish_scripts_dir/nb.rs $argv; end
function build_gantt; $__fish_scripts_dir/build_gantt.rs $argv; end
# `-L` asks for nix's own streamed view; anything else that isn't an interactive build or run is untouched
function nix
	if not status is-interactive; or not test -t 1; or contains -- -L $argv; or contains -- --print-build-logs $argv
		command nix $argv
		return
	end
	switch "$argv[1]"
		case build
			build_gantt nix $argv
		case run
			set -l pre $argv[2..]
			if set -l sep (contains -i -- -- $argv)
				set pre $argv[2..(math $sep - 1)]
				test $sep -gt 2; or set pre
			end
			set -l inst (string match -v -- '-*' $pre)[1]
			set -q inst[1]; or set inst .
			set -l flake (string split -m1 '#' -- $inst) default
			test -n "$flake[2]"; or set flake[2] default
			# apps aren't buildable; `nix run` prefers them over packages of the same name
			if not command nix eval "$flake[1]#apps."(uname -m)"-linux.$flake[2].type" >/dev/null 2>&1
				build_gantt nix build --no-link $pre; or return
			end
			command nix $argv
		case '*'
			command nix $argv
	end
end
function gn; $__fish_scripts_dir/git_scripts.rs publish $argv; end
function kbd; $__fish_scripts_dir/kbd.rs $argv; end
function health; $__fish_scripts_dir/health.rs $argv; end
function optimize_for; sudo -E $__fish_scripts_dir/optimize_for.rs $argv; end
function smart_shutdown; $NIXOS_CONFIG/home/scripts/smart_shutdown.rs $argv; end
# plain `shutdown now` skips the claude inventory write, silently breaking restore_sessions
function shutdown
	if contains -- -r $argv; or contains -- --reboot $argv
		smart_shutdown --reboot
	else
		smart_shutdown
	end
end
function reboot; smart_shutdown --reboot $argv; end
function save_sessions; $NIXOS_CONFIG/home/scripts/save_sessions.rs $argv; end # not the store copy: a shell older than the last switch would record in a format `restore_sessions` no longer reads
function supervise_sessions; $__fish_scripts_dir/supervise_sessions.rs $argv; end
function claude_sessions; $__fish_scripts_dir/claude_sessions/main.rs $argv; end

# Run the claude_sessions classifier snapshot tests. Wraps the nightly
# toolchain resolution the cargo-script runner already cached, so you don't
# retype the RUST_PATH/PATH dance. Extra args pass straight through to cargo,
# e.g. `claude_sessions_test -- --nocapture`. Set INSTA_UPDATE=always to
# record snapshots for newly added fixtures.
function claude_sessions_test
    set -l rust_path (cat $HOME/.cargo/target/.rust-store-path)
    env RUSTC_WRAPPER="" PATH="$rust_path/bin:$PATH" \
        "$rust_path/bin/cargo" -Zscript test \
        --manifest-path "$NIXOS_CONFIG/home/scripts/claude_sessions/main.rs" $argv # not the store copy: INSTA_UPDATE writes snapshots next to it
end
function profile_shell; $NIXOS_CONFIG/scripts/profile_shell.rs $argv; end
function ambiance; $__fish_scripts_dir/ambiance.rs $argv; end
function pp; $__fish_scripts_dir/pp.rs $argv; end
function ex; $__fish_scripts_dir/excalidraw/main.rs $argv; end

function __run_pic_script
    set -l ext png
    if test "$argv[1]" = "--type"
        set ext $argv[2]
        set -e argv[1..2]
    end
    set -l script $argv[1]
    set -l script_args $argv[2..-1]
    set -l out /tmp/__pic_gen_script_out.$ext
    $script -o $out $script_args
    and xdg-open $out 2>/dev/null
end

function indexes
    __run_pic_script --type html $__fish_scripts_dir/gen_pics/indexes.rs $argv
end

function git_scripts; $__fish_scripts_dir/git_scripts.rs $argv; end
function gfork; $__fish_scripts_dir/git_scripts.rs fork $argv; end
function gpr; $__fish_scripts_dir/git_scripts.rs pr $argv; end
function gp; $__fish_scripts_dir/git_scripts.rs push $argv; end
function gpf; $__fish_scripts_dir/git_scripts.rs push --force $argv; end
function gpl; $__fish_scripts_dir/git_scripts.rs push --force-with-lease $argv; end
function gbd; $__fish_scripts_dir/git_scripts.rs delete $argv; end

function gc
	if contains -- -c $argv
		set -l result ($__fish_scripts_dir/git_clone.rs $argv)
		and cd $result
	else
		$__fish_scripts_dir/git_clone.rs $argv
	end
end

function choose_port; $__fish_scripts_dir/choose_port.sh $argv; end

set -l __maintenance_config (string collect < $XDG_CONFIG_HOME/maintenance/config.json) # from home/scripts/maintenance/config.nix
if test (random 0 999) -lt (math -s0 (string match -rg '"warn_probability":([\d.]+)' -- $__maintenance_config) \* 1000)
    set -l due "$XDG_STATE_HOME/fish/maintenance_due" # maintenance/main.rs writes it: its run + horizon_long
    if not test -f $due
        echo "Warning: maintenance has never been run. Run 'up' to update."
    else if test (date +%s) -gt (string collect < $due)
        echo "Warning: maintenance is overdue. Run 'up' to update."
    end
end

function cross_project_version_alignment; $__fish_scripts_dir/maintenance/cross_project_version_alignment.rs $argv; end
