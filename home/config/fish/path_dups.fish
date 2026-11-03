# Warns when a command name is provided by several PATH dirs (eg nix + `cargo binstall`).
# Rescans only when the dirs or their mtimes change; universal key, so each change is reported once, not per shell.
function __path_dups_check --on-event fish_postexec
    set -l shown
    set -l real
    # /nix/store and .direnv: devshells shadow on purpose. /run/wrappers: exists to shadow system-path.
    for d in (path filter -d $PATH | string match -v -e /nix/store/ | string match -v -e /.direnv/ | string match -v /run/wrappers/bin)
        set -l r (path resolve $d)
        contains -- $r $real; and continue
        set -a shown $d
        set -a real $r
    end
    set -l key (string join ' ' $real (path mtime $real))
    test "$key" = "$__path_dups_key"; and return
    set -U __path_dups_key $key

    set -l groups
    set -l members
    for line in (find -L $real -mindepth 1 -maxdepth 1 -type f -executable -printf '%f\t%h\n' | awk -F'\t' '{ d[$1] = d[$1] "\t" $2; c[$1]++ } END { for (n in c) if (c[n] > 1) print n d[n] }' | LC_ALL=C sort)
        set -l parts (string split \t -- $line)
        set -l name $parts[1]
        set -l dirs $parts[2..]
        test (count (path resolve $dirs/$name | path sort -u)) -gt 1; or continue # same binary reached via several profiles
        set -l where
        for dir in $dirs
            set -l d (path normalize $shown[(contains -i -- $dir $real)] | string trim -r -c /)
            switch $d
                case /run/current-system/sw/bin
                    set d 'System Packages'
                case /etc/profiles/per-user/$USER/bin
                    set d 'Home Manager'
            end
            set -a where (string replace -r "^$HOME" '~' -- $d)
        end
        set -l group (string join ' vs ' $where)
        set -l i (contains -i -- $group $groups); or begin
            set -a groups $group
            set -a members ''
            set i (count $groups)
        end
        set members[$i] "$members[$i]"\n"  - $name"
    end
    test (count $groups) -gt 0; or return
    set -l out 'PATH dup (first wins):'
    for i in (seq (count $groups))
        set -a out "- $groups[$i]$members[$i]"
    end
    echo (set_color yellow)(string join \n -- $out | string collect)(set_color normal) >&2
end
status is-interactive; and __path_dups_check
