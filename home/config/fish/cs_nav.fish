alias cc="cd && clear"

function csc
    set _path "$NIXOS_CONFIG/home/config/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

function css
    set _path "$HOME/s/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

function csh
    set _path "$NIXOS_CONFIG/home/scripts/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

function csd
    set _path "$HOME/Downloads/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

function csl
    set _path "$HOME/s/l/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

function csr
    set _path "$HOME/trading/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

function csst
    set _path "$HOME/s/tmp/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

function cst
    set _path "$HOME/tmp/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

function csg
    set _path "$HOME/g/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

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

function csb
    set _path "$HOME/Documents/Books/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

function csp
    set _path "$HOME/Documents/Papers/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

function csn
    set _path "$HOME/nix/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

function csu
    set _path "$HOME/uni/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end

function csm
    set _path "$HOME/math/"
    if test -n "$argv[1]"
        set _path "$_path$argv[1]"
    end
    cs $_path
end
