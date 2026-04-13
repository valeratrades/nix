function cl
    set -l base_cmd claude --dangerously-skip-permissions
    set -l repo (command git rev-parse --show-toplevel 2>/dev/null)

    if [ -n "$repo" ] && [ -f "$repo/AGENTS.md" ]
        command $base_cmd --append-system-prompt "$(cat "$repo/AGENTS.md")" $argv
    else
        command $base_cmd $argv
    end
end
complete -c cl -w claude
