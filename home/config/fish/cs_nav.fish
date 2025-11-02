alias cc="cd && clear"

function csc
    set _path "$NIXOS_CONFIG/home/config/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c csc -x -a "(cd $NIXOS_CONFIG/home/config/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function css
    set _path "$HOME/s/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c css -x -a "(cd $HOME/s/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function csh
    set _path "$NIXOS_CONFIG/home/scripts/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c csh -x -a "(cd $NIXOS_CONFIG/home/scripts/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function csd
    set _path "$HOME/Downloads/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c csd -x -a "(cd $HOME/Downloads/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function csl
    set _path "$HOME/s/l/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c csl -x -a "(cd $HOME/s/l/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function csr
    set _path "$HOME/trading/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c csr -x -a "(cd $HOME/trading/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function cso
    set _path "$HOME/s/other/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c cso -x -a "(cd $HOME/s/other/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function csst
    set _path "$HOME/s/tmp/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c csst -x -a "(cd $HOME/s/tmp/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function cst
    set _path "$HOME/tmp/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c cst -x -a "(cd $HOME/tmp/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function csg
    set _path "$HOME/g/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c csg -x -a "(cd $HOME/g/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function cssg
    set _path "$HOME/s/g/"
    set parent 0
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
        set parent 1
    end
    cs $_path
    if test $parent = 1
        git pull
    end
end
complete -c cssg -x -a "(cd $HOME/s/g/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function csb
    set _path "$HOME/Documents/Books/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c csb -x -a "(cd $HOME/Documents/Books/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function csp
    set _path "$HOME/Documents/Papers/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c csp -x -a "(cd $HOME/Documents/Papers/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function csn
    set _path "$HOME/nix/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c csn -x -a "(cd $HOME/nix/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function csu
    set _path "$HOME/uni/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c csu -x -a "(cd $HOME/uni/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"

function csm
    set _path "$HOME/math/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
complete -c csm -x -a "(cd $HOME/math/ 2>/dev/null && __fish_complete_directories | string replace -r '^' '')"
