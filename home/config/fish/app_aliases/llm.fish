function cl
    set -l base_cmd claude --dangerously-skip-permissions
    set -l repo (command git rev-parse --show-toplevel 2>/dev/null)
    set -l no_verify 0
    set -l passthrough_args
    set -l expect_model 0

    for arg in $argv
        if [ $expect_model -eq 1 ]
            set -a passthrough_args --model $arg
            set expect_model 0
        else if [ "$arg" = --no-verify ]
            set no_verify 1
        else if [ "$arg" = -m ]
            set expect_model 1
        else
            set -a passthrough_args $arg
        end
        #TODO: add `-p` for opening in plan mode over a specific file
    end

    if [ $expect_model -eq 1 ]
        echo "cl: -m requires a model argument" >&2
        return 1
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

function clp
    cl --permission-mode plan "Plan file: $argv[1]. Select it and submit for approval (approval, - do not start execution)" $argv[2..]
end

# clr - random code quality upkeep. Picks one hardcoded prompt at random and starts cl on it.
function clr
    set -l prompts \
        "Find the single worst public function in this codebase that should be private or removed entirely, and refactor to shrink the module boundary. Remove > refactor > add." \
        "Hunt for one fallback that masks tainted state (unwrap_or, let _ =, silent default) and replace it with a loud panic/error at the earliest point the state goes bad." \
        "Find a place where an invariant is assumed but not asserted, and add the assert. Pick the assertion that would catch the nastiest latent bug." \
        "Locate the most duplicated logic in the codebase and collapse it into a single source of truth, preferring std trait impls (From, etc) over a new helper fn." \
        "Find the worst error-handling site (a swallowed error, a vague message, a stringly-typed error) and improve it with thiserror/miette/proper context." \
        "Pick the most confusingly-named symbol in the codebase and rename it to something that matches what it actually does. Update all call sites." \
        "Find dead code, unused pub items, or unreachable branches and delete them. Verify nothing depends on them first." \
        "Find one function doing too much and split its responsibilities, or find an over-abstracted indirection and inline it. Whichever makes the code simpler." \
        "Identify the area with the weakest test coverage relative to its importance, and add a focused test that captures real behavior (read matklad's how-to-test first)."

    set -l choice $prompts[(random 1 (count $prompts))]
    echo "clr → $choice" >&2
    cl $choice $argv
end
