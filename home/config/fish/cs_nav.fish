alias cc="cd && clear"

# name => base path. Each generates a `cs` shortcut that takes an optional
# path suffix (first non-flag arg) and forwards any flags (-t, -a, …) to `cs`.
set -l _cs_navs \
    csc "$NIXOS_CONFIG/home/config/" \
    csd "$HOME/Downloads/" \
    css "$HOME/s/" \
    cse "$HOME/s/ev_invest/" \
    csq "$HOME/s/ev_invest/_quant/" \
    csa "$HOME/s/ev_invest/_service_arb/" \
    csre "$HOME/s/ev_invest/_estate/" \
    csr "$HOME/trading/" \
    csh "$NIXOS_CONFIG/home/scripts/" \
    csm "$HOME/math/" \
    cso "$HOME/s/other/" \
    csg "$HOME/g/" \
    cst "$HOME/tmp/" \
    csb "$HOME/Documents/Books/" \
    csp "$HOME/Documents/Papers/" \
    csl "$HOME/s/l/" \
    csst "$HOME/s/tmp/" \
    csn "$HOME/nix/" \
    csu "$HOME/uni/" \

for i in (seq 1 2 (count $_cs_navs))
    set -l name $_cs_navs[$i]
    set -l base $_cs_navs[(math $i + 1)]

    function $name --inherit-variable base
        set -l flags
        set -l suffix
        for arg in $argv
            switch $arg
                case '-*'
                    set -a flags $arg
                case '*'
                    set suffix $arg
            end
        end
        set -l _path "$base$suffix"
        cs $_path $flags
    end
    complete -c $name -x -a "(cd $base 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"
end

# `cssg` is special: it also `git pull`s when given a subdirectory.
function cssg
    set -l flags
    set -l suffix
    for arg in $argv
        switch $arg
            case '-*'
                set -a flags $arg
            case '*'
                set suffix $arg
        end
    end
    set -l _path "$HOME/s/g/$suffix"
    cs $_path $flags
    if test -n "$suffix"
        git pull
    end
end
complete -c cssg -x -a "(cd $HOME/s/g/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"
