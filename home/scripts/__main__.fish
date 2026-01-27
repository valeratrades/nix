set __fish_scripts_dir (dirname (status --current-filename))
source $__fish_scripts_dir/videos.fish
source $__fish_scripts_dir/server.fish
source $__fish_scripts_dir/weird/__main__.fish
source $__fish_scripts_dir/document_watch.fish

function beep
	$__fish_scripts_dir/beep.rs $__fish_scripts_dir/assets/sound/Notification.mp3 $argv
end

alias 2fa="$__fish_scripts_dir/2fa.rs"
alias timer="$__fish_scripts_dir/timer.rs"
alias theme="$__fish_scripts_dir/theme_toggle.rs"
alias mvd="$__fish_scripts_dir/mvd.rs"
alias translate_book="$__fish_scripts_dir/translate_book.rs"
alias clipboard_to_keystrokes="$__fish_scripts_dir/clipboard_to_keystrokes.rs"
alias eww_open_on="$__fish_scripts_dir/eww_open_on.rs"
alias bluetooth="$__fish_scripts_dir/bluetooth.rs"
alias cnix_release="$__fish_scripts_dir/cnix_release.rs"
alias nb="$__fish_scripts_dir/nb.rs"
alias gn="$__fish_scripts_dir/git_scripts.rs publish"
alias kbd="$__fish_scripts_dir/kbd.rs"
alias optimize_for="sudo -E $__fish_scripts_dir/optimize_for.rs"
alias smart_shutdown="$__fish_scripts_dir/smart_shutdown.rs"
alias profile_shell_init="$__fish_scripts_dir/maintenance/profile_shell_init.rs"
alias ambiance="$__fish_scripts_dir/ambiance.rs"

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

alias git_scripts="$__fish_scripts_dir/git_scripts.rs"
alias gfork="$__fish_scripts_dir/git_scripts.rs fork"
alias gpr="$__fish_scripts_dir/git_scripts.rs pr"
alias gp="$__fish_scripts_dir/git_scripts.rs push"
alias gpf="$__fish_scripts_dir/git_scripts.rs push --force"
alias gpl="$__fish_scripts_dir/git_scripts.rs push --force-with-lease"
alias gbd="$__fish_scripts_dir/git_scripts.rs delete"

alias choose_port="$__fish_scripts_dir/choose_port.sh"

set -g __maintenance_last_run "$XDG_STATE_HOME/fish/maintenance_last_run"

# Warn if maintenance hasn't been run in over a month
if test -f $__maintenance_last_run
    set -l last_run (cat $__maintenance_last_run)
    set -l now (date +%s)
    set -l month_seconds 2592000 # 30 days
    if test (math $now - $last_run) -gt $month_seconds
        echo "Warning: maintenance hasn't been run in over a month. Run 'up' to update."
    end
else
    echo "Warning: maintenance has never been run. Run 'up' to update."
end

alias cross_project_version_alignment="$__fish_scripts_dir/maintenance/cross_project_version_alignment.rs"
