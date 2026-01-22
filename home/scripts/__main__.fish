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

set -g __check_nightly_versions_cache "$XDG_STATE_HOME/fish/nightly_version_files.txt"
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

function check_nightly_versions
    set -l mode --known
    set -l search_dirs

    # Parse arguments
    for arg in $argv
        switch $arg
            case --discover
                set mode --discover
            case --known
                set mode --known
            case '*'
                set -a search_dirs $arg
        end
    end

    # Default search dirs if none provided
    if test (count $search_dirs) -eq 0
        set search_dirs ~/s ~/nix/home/scripts
    end

    set -l has_warning 0
    set -l nightly_versions
    set -l files_to_check

    if test "$mode" = "--discover"
        # Discovery mode: find all relevant files and cache them
        mkdir -p (dirname $__check_nightly_versions_cache)
        : > $__check_nightly_versions_cache

        for search_dir in $search_dirs
            set search_dir (eval echo $search_dir)
            if not test -d "$search_dir"
                echo "Warning: $search_dir is not a directory"
                set has_warning 1
                continue
            end

            # Use fd to find .rs files that contain nightly patterns
            # Only .rs scripts need pinned versions; proper projects with flake.nix can use selectLatestNightlyWith
            for script in (fd -t f -e rs . "$search_dir" 2>/dev/null)
                if grep -qE 'selectLatestNightlyWith|nightly\."[0-9]{4}-[0-9]{2}-[0-9]{2}"' "$script" 2>/dev/null
                    echo "$script" >> $__check_nightly_versions_cache
                    set -a files_to_check "$script"
                end
            end
        end

        echo "Discovered "(count $files_to_check)" files with nightly references, cached to $__check_nightly_versions_cache"
    else
        # Known mode: use cached file list
        if not test -f $__check_nightly_versions_cache
            echo "Error: No cached file list. Run with --discover first."
            return 1
        end

        while read -l line
            if test -n "$line" -a -f "$line"
                set -a files_to_check "$line"
            end
        end < $__check_nightly_versions_cache
    end

    # Check files with single rg call
    if test (count $files_to_check) -gt 0
        # Single rg call for both patterns, limit to first match per file
        for match in (rg -m1 --with-filename '(selectLatestNightlyWith|nightly\."[0-9]{4}-[0-9]{2}-[0-9]{2}")' $files_to_check 2>/dev/null)
            set -l file (string split -m1 ':' $match)[1]
            if string match -q '*selectLatestNightlyWith*' -- $match
                echo "Warning: $file uses selectLatestNightlyWith instead of pinned nightly version"
                set has_warning 1
            else
                set -l version (string match -r '[0-9]{4}-[0-9]{2}-[0-9]{2}' $match)
                if test -n "$version"
                    set -a nightly_versions "$version:$file"
                end
            end
        end
    end

    # Check if all versions are the same
    if test (count $nightly_versions) -gt 0
        set -l first_version (string split ':' $nightly_versions[1])[1]

        for entry in $nightly_versions
            set -l current_version (string split ':' $entry)[1]
            set -l current_script (string split ':' $entry)[2]

            if test "$current_version" != "$first_version"
                echo "Warning: $current_script uses nightly version $current_version (expected $first_version)"
                set has_warning 1
            end
        end
    end

    return $has_warning
end
# check_nightly_versions --known is too slow for shell startup (~10ms for rg call)
# Run during --discover (maintenance) instead
