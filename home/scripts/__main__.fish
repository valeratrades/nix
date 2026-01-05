set fish_scripts_pdir (dirname (status --current-filename))
source $fish_scripts_pdir/videos.fish
source $fish_scripts_pdir/server.fish
source $fish_scripts_pdir/weird/__main__.fish
source $fish_scripts_pdir/document_watch.fish

function beep
	$fish_scripts_pdir/beep.rs $fish_scripts_pdir/assets/sound/Notification.mp3 $argv
end

alias 2fa="$fish_scripts_pdir/2fa.rs"
alias timer="$fish_scripts_pdir/timer.rs"
alias theme="$fish_scripts_pdir/theme_toggle.rs"
alias mvd="$fish_scripts_pdir/mvd.rs"
alias translate_book="$fish_scripts_pdir/translate_book.rs"
alias clipboard_to_keystrokes="$fish_scripts_pdir/clipboard_to_keystrokes.rs"
alias eww_open_on="$fish_scripts_pdir/eww_open_on.rs"
alias bluetooth="$fish_scripts_pdir/bluetooth.rs"
alias cnix_release="$fish_scripts_pdir/cnix_release.rs"
alias nb="$fish_scripts_pdir/nb.rs"
alias gn="$fish_scripts_pdir/git_scripts.rs publish"
alias kbd="$fish_scripts_pdir/kbd.rs"
alias optimize_for="sudo $fish_scripts_pdir/optimize_for.rs"
alias smart_shutdown="$fish_scripts_pdir/smart_shutdown.rs"
alias profile_shell_init="$fish_scripts_pdir/profile_shell_init.rs"

alias git_scripts="$fish_scripts_pdir/git_scripts.rs"
alias gfork="$fish_scripts_pdir/git_scripts.rs fork"
alias gpr="$fish_scripts_pdir/git_scripts.rs pr"
alias gp="$fish_scripts_pdir/git_scripts.rs push"
alias gpf="$fish_scripts_pdir/git_scripts.rs push --force"
alias gpl="$fish_scripts_pdir/git_scripts.rs push --force-with-lease"
alias gbd="$fish_scripts_pdir/git_scripts.rs delete"

alias choose_port="$fish_scripts_pdir/choose_port.sh"

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
