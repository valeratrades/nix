set fish_scripts_pdir (dirname (status --current-filename))
source $fish_scripts_pdir/videos.fish
source $fish_scripts_pdir/server.fish
source $fish_scripts_pdir/weird/mod.fish
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

alias choose_port="$fish_scripts_pdir/choose_port.sh"

function check_nightly_versions
    set -l script_dir (dirname (status --current-filename))
    set -l nightly_versions
    set -l has_warning 0

    # Find all .rs files in the script directory and subdirectories
    for script in $script_dir/**/*.rs
        if test -f "$script"
            # Check for selectLatestNightlyWith usage
            if grep -q 'selectLatestNightlyWith' "$script" 2>/dev/null
                echo "Warning: $script uses selectLatestNightlyWith instead of pinned nightly version"
                set has_warning 1
                continue
            end

            # Extract nightly version (format: nightly."YYYY-MM-DD")
            set -l _version (grep -oP 'nightly\."\K[0-9]{4}-[0-9]{2}-[0-9]{2}' "$script" 2>/dev/null)

            if test -n "$_version"
                set -a nightly_versions "$_version:$script"
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
check_nightly_versions
