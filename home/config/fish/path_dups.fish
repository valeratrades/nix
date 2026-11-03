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

    for line in (find -L $real -mindepth 1 -maxdepth 1 -type f -executable -printf '%f\t%h\n' | awk -F'\t' '{ d[$1] = d[$1] "\t" $2; c[$1]++ } END { for (n in c) if (c[n] > 1) print n d[n] }' | sort)
        set -l parts (string split \t -- $line)
        set -l name $parts[1]
        set -l dirs $parts[2..]
        test (count (path resolve $dirs/$name | path sort -u)) -gt 1; or continue # same binary reached via several profiles
        set -l where
        for dir in $dirs
            set -a where (string replace -r "^$HOME" '~' -- $shown[(contains -i -- $dir $real)])
        end
        echo (set_color yellow)"PATH dup: `$name` in $(string join ', ' $where) (first wins)"(set_color normal) >&2
    end
end
status is-interactive; and __path_dups_check
