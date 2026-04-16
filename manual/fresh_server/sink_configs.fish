#!/usr/bin/env fish
# Pushes all configs from fresh_server/.config to the server,
# running reasonable_envsubst on each, and printing diffs for any changes.

set script_dir (dirname (realpath (status --current-filename)))
set config_dir "$script_dir/.config"
set server $MAIN_SERVER_SSH_HOST

if test -z "$server"
    echo "MAIN_SERVER_SSH_HOST is not set"
    exit 1
end

for local_file in $config_dir/*
    set filename (basename $local_file)
    set remote_path "~/.config/$filename"

    # use temp files, not command substitution: fish's $(...) strips trailing newlines
    # and splits on newlines into a list, so echo-ing it collapses multiline content to one line
    cat $local_file | reasonable_envsubst - > /tmp/_sink_substituted
    ssh $server "cat $remote_path 2>/dev/null" > /tmp/_sink_remote 2>/dev/null

    if diff -q /tmp/_sink_remote /tmp/_sink_substituted > /dev/null 2>&1
        echo "  [ok] $filename"
    else
        echo "  [update] $filename"
        diff /tmp/_sink_remote /tmp/_sink_substituted | sed 's/^/    /'
        ssh $server "cat > $remote_path" < /tmp/_sink_substituted
    end
end
