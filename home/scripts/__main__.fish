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
function cargo_clean; $__fish_scripts_dir/cargo_clean.rs $argv; end
function translate_book; $__fish_scripts_dir/translate_book.rs $argv; end
function clipboard_to_keystrokes; $__fish_scripts_dir/clipboard_to_keystrokes.rs $argv; end
function eww_open_on; $__fish_scripts_dir/eww_open_on.rs $argv; end
function bluetooth; $__fish_scripts_dir/bluetooth.rs $argv; end
function cnix_release; $__fish_scripts_dir/cnix_release.rs $argv; end
function nb; $__fish_scripts_dir/nb.rs $argv; end
function gn; $__fish_scripts_dir/git_scripts.rs publish $argv; end
function kbd; $__fish_scripts_dir/kbd.rs $argv; end
function health; $__fish_scripts_dir/health.rs $argv; end
function optimize_for; sudo -E $__fish_scripts_dir/optimize_for.rs $argv; end
function smart_shutdown; $NIXOS_CONFIG/home/scripts/smart_shutdown.rs $argv; end # not the store copy: a shell older than the last switch would record in a format `restore_sessions` no longer reads
# plain `shutdown now` skips the claude inventory write, silently breaking restore_sessions
function shutdown
	if contains -- -r $argv; or contains -- --reboot $argv
		smart_shutdown --reboot
	else
		smart_shutdown
	end
end
function reboot; smart_shutdown --reboot $argv; end
function save_sessions; smart_shutdown --save-only $argv; end
function supervise_sessions; $__fish_scripts_dir/supervise_sessions.rs $argv; end
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

set -g __maintenance_last_run "$XDG_STATE_HOME/fish/maintenance_last_run"

# Warn if maintenance hasn't been run in over a month
if test -f $__maintenance_last_run
    set -l month_seconds 2592000 # 30 days
    if test (path mtime --relative $__maintenance_last_run) -gt $month_seconds # mtime: maintenance.rs rewrites the stamp on every run
        echo "Warning: maintenance hasn't been run in over a month. Run 'up' to update."
    end
else
    echo "Warning: maintenance has never been run. Run 'up' to update."
end

function cross_project_version_alignment; $__fish_scripts_dir/maintenance/cross_project_version_alignment.rs $argv; end
