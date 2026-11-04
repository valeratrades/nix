# Warns on vars the systemd user env (what units, and the tmux server they restore, start from) holds with another value, or holds that this shell lacks.
# Names only: values include secrets. Probed in the background (systemctl+jq cost ~15ms), reported at the next prompt; universal key, so each set is reported once, not per shell.
status is-interactive; or return

set -g __env_fights_out $XDG_RUNTIME_DIR/env_fights.$fish_pid
command sh -c 'systemctl --user show-environment -o json | jq -r --rawfile inh "/proc/$1/environ" "$2" > "$3.tmp" && mv "$3.tmp" "$3"' _ $fish_pid '
    ($inh | split("\u0000") | map(select(length > 0) | capture("^(?<key>[^=]*)=(?<value>.*)$"; "s")) | from_entries) as $in
    | . as $sd | keys[] as $k
    | select($k | IN("PWD", "OLDPWD", "SHLVL", "_", "TERM", "DESKTOP_STARTUP_ID", "XDG_ACTIVATION_TOKEN") | not) # per-process or per-launch by nature
    | select($ENV[$k] == null or ($ENV[$k] | contains($sd[$k]) | not)) # a shell list extending the systemd one is no fight
    | (if $ENV[$k] == null then "shell lacks" elif $in[$k] == $ENV[$k] then "inherited" else "set by fish config" end) + "\t" + $k
' $__env_fights_out &>/dev/null &
disown

function __env_fights_report --on-event fish_postexec
    test -f $__env_fights_out; or return
    set -l lines (cat $__env_fights_out)
    rm $__env_fights_out
    functions -e __env_fights_report
    set -l key (string join ' ' $lines)
    test "$key" = "$__env_fights_key"; and return
    set -U __env_fights_key $key
    test (count $lines) -gt 0; or return
    set -l out 'env vs systemd --user (units and the tmux server start from the latter):'
    for kind in 'shell lacks' inherited 'set by fish config'
        set -l names (string match -- "$kind"\t'*' $lines | string replace -- "$kind"\t '')
        test (count $names) -gt 0; and set -a out "- $kind: $names"
    end
    echo (set_color yellow)(string join \n -- $out | string collect)(set_color normal) >&2
end
