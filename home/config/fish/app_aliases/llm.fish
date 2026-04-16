function cl
    set -l base_cmd claude --dangerously-skip-permissions
    set -l repo (command git rev-parse --show-toplevel 2>/dev/null)

    if [ -n "$repo" ] && [ -f "$repo/AGENTS.md" ]
        if not git -C $repo check-ignore -q -- .claude/
            echo "cl: AGENTS.md found, but .claude/ is not excluded in .gitignore" >&2
            echo "    Add '.claude/' to $repo/.gitignore to avoid committing LLM-specific files" >&2
            return 1
        end
        if not test -f "$repo/.claude/CLAUDE.md"
            mkdir -p "$repo/.claude"
            echo "@../AGENTS.md" > "$repo/.claude/CLAUDE.md"
        end
    end

    command $base_cmd --append-system-prompt (cat $HOME/.claude/daneel.md) $argv
end
complete -c cl -w claude
