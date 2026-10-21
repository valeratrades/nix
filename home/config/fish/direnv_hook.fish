# Replaces `direnv hook fish` (installed as direnv's vendor_conf.d by hosts/hm-shared/home.nix). See github.com/valeratrades/nix/issues/22 (5a/5b).
# - skips the `direnv export` spawn while the same .envrc stays loaded and none of its watched files changed
# - a fresh shell (nothing loaded) reuses the last export of that .envrc when it is provably the same: watched mtimes, base values of every var it changes, its nix store paths still present, and < 24h old (so shellHook side effects still run at least daily)

set -g __direnv_bin @direnv@
set -g __direnv_cache_dir $XDG_CACHE_HOME/direnv_fish

function __direnv_sync --on-event fish_prompt
    set -l rc
    set -l d $PWD
    while true
        if test -f $d/.envrc
            set rc $d/.envrc
            break
        end
        test "$d" = /; and break
        set d (path dirname $d)
    end

    if set -q DIRENV_FILE
        if test "$rc" = "$DIRENV_FILE"; and set -q __direnv_watch[1]; and test "$(string join \n -- $__direnv_mtimes)" = "$(__direnv_mtimes $__direnv_watch)"
            return
        end
    else
        test -n "$rc"; or return
        __direnv_from_cache $rc; and return
    end
    __direnv_full $rc
end

function __direnv_on_pwd --on-variable PWD
    status is-interactive; and __direnv_sync
end

function __direnv_mtimes
    for f in $argv
        path mtime $f; or echo 0
    end
end

# `name\x1fvalue` per var: escaped elements, or a marker for unset
function __direnv_values
    for n in $argv
        if not set -q $n
            echo $n\x1f\x1eunset
            continue
        end
        set -l v (string escape -- $$n)
        echo "$n"\x1f"$v"
    end
end

function __direnv_cache_file -a rc
    echo $__direnv_cache_dir/(string replace -a / % -- $rc)
end

function __direnv_from_cache -a rc
    set -l c (__direnv_cache_file $rc)
    test -f $c.meta; or return 1
    test (path mtime --relative $c.meta) -lt 86400; or return 1
    source $c.meta # sets -f: watch, mtimes, names, values, store_paths
    test "$(string join \n -- $mtimes)" = "$(__direnv_mtimes $watch)"; or return 1
    test "$(string join \n -- $values)" = "$(__direnv_values $names)"; or return 1
    for p in $store_paths
        test -e $p; or return 1
    end
    source $c.export
    set -g __direnv_watch $watch
    set -g __direnv_mtimes $mtimes
end

function __direnv_full -a rc
    set -l fresh (not set -q DIRENV_FILE; and echo 1)
    set -l before (__direnv_values (set -n -x))
    set -l before_path $PATH

    set -l out ($__direnv_bin export fish | string collect)
    set -l ok $pipestatus[1]
    printf '%s' $out | source
    set -e __direnv_watch __direnv_mtimes
    set -q DIRENV_FILE; or return

    set -l watch
    for w in (string match -rg '^Loaded watch: "(.*)" - ' -- ($__direnv_bin status))
        set -a watch (path resolve (path dirname $DIRENV_FILE)/$w)
    end
    contains -- $DIRENV_FILE $watch; or begin
        echo "direnv_hook: watch list from `direnv status` doesn't contain $DIRENV_FILE; parsing broke" >&2
        return 1
    end
    set -g __direnv_watch $watch
    set -g __direnv_mtimes (__direnv_mtimes $watch)

    test "$fresh" = 1 -a "$ok" = 0 -a "$DIRENV_FILE" = "$rc"; or return # only a load from nothing replays into another fresh shell
    set -l after (__direnv_values (set -n -x))
    set -l after_names (string split -m1 -f1 \x1f -- $after)
    # every var the export changed, added or removed; escaped values hold no newlines, so lines are safe set elements
    set -l changed (printf '%s\n' $after $before $before | LC_ALL=C command sort | command uniq -u | string split -m1 -f1 \x1f)
    set -l removed (printf '%s\n' $after_names $after_names (string split -m1 -f1 \x1f -- $before) | LC_ALL=C command sort | command uniq -u)
    set -l names $changed $removed
    set -l values # pre-load `name\x1fvalue` of each
    for n in $names
        set -l was (string match -- $n\x1f'*' $before) # var names are [A-Za-z0-9_], so no glob chars
        set -a values (test -n "$was"; and echo $was; or echo $n\x1f\x1eunset)
    end
    set -l store_paths
    for p in (string match -- '/nix/store/*' $PATH)
        contains -- $p $before_path; or set -a store_paths $p
    end

    set -l c (__direnv_cache_file $rc)
    mkdir -p $__direnv_cache_dir
    printf '%s' $out >$c.export.tmp
    begin
        echo set -f watch (string escape -- $watch)
        echo set -f mtimes (string escape -- $__direnv_mtimes)
        echo set -f names (string escape -- $names)
        echo set -f values (string escape -- $values)
        echo set -f store_paths (string escape -- $store_paths)
    end >$c.meta.tmp
    command mv $c.export.tmp $c.export
    command mv $c.meta.tmp $c.meta # last: .meta present means .export is complete
end
