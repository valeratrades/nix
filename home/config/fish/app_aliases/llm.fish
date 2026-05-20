function cl
    set -l base_cmd claude --dangerously-skip-permissions
    set -l repo (command git rev-parse --show-toplevel 2>/dev/null)
    set -l no_verify 0
    set -l passthrough_args

    for arg in $argv
        if [ "$arg" = --no-verify ]
            set no_verify 1
        else
            set -a passthrough_args $arg
        end
        #TODO: add `-p` for opening in plan mode over a specific file
    end

    if [ $no_verify -eq 0 ] && [ -n "$repo" ] && [ -f "$repo/AGENTS.md" ]
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

    command $base_cmd --append-system-prompt (cat $HOME/.claude/daneel.md) $passthrough_args
end
complete -c cl -w claude

function cld
    set -lx ANTHROPIC_BASE_URL 'https://api.deepseek.com/anthropic'
    set -lx ANTHROPIC_AUTH_TOKEN "$DEEPSEEK_KEY"
    set -lx ANTHROPIC_MODEL 'deepseek-v4-pro[1m]'
    set -lx ANTHROPIC_DEFAULT_SONNET_MODEL 'deepseek-v4-pro[1m]'
    set -lx ANTHROPIC_DEFAULT_OPUS_MODEL 'deepseek-v4-pro[1m]'
    set -lx ANTHROPIC_DEFAULT_HAIKU_MODEL 'deepseek-v4-flash[1m]'

    cl $argv
end
