# dirs where fable is forced and opus is refused; matches the dir itself and anything under it
set -g utmost_importance_projects $HOME/ev_invest/trading_data $HOME/ev_invest/risk_management

# --acc N | -a N selects credentials in ~/.claude-accountN; without it, default ~/.claude (master)
function claude
    set -l args
    set -l acc
    set -l i 1
    while [ $i -le (count $argv) ]
        if contains -- $argv[$i] --acc -a
            set i (math $i + 1)
            set acc $argv[$i]
            if [ -z "$acc" ]
                echo "claude: --acc requires an account number" >&2
                return 1
            end
        else
            set -a args $argv[$i]
        end
        set i (math $i + 1)
    end
    if set -q acc[1]
        set -lx CLAUDE_CONFIG_DIR $HOME/.claude-account$acc
        if not test -f $CLAUDE_CONFIG_DIR/.credentials.json
            echo "claude: no credentials at $CLAUDE_CONFIG_DIR" >&2
            return 1
        end
        command claude $args
    else
        command claude $args
    end
end

function cl
    if [ "$argv[1]" = review ]
        # picker echoes its own choice to stderr
        set -l prompt ($HOME/s/codestyle/skills/pick.rs (pwd -P) | string collect)
        if [ -z "$prompt" ]
            return 1
        end
        cl $prompt $argv[2..]
        return
    end

    set -l base_cmd claude --dangerously-skip-permissions
    set -l repo (command git rev-parse --show-toplevel 2>/dev/null)
    set -l no_verify 0
    set -l passthrough_args
    set -l expect_model 0

    set -l model
    set -l resume_n

    for arg in $argv
        if [ $expect_model -eq 1 ]
            set model $arg
            set expect_model 0
        else if string match -qr '^-[1-9]$' -- $arg
            set resume_n (string sub -s 2 -- $arg)
        else if [ "$arg" = --no-verify ]
            set no_verify 1
        else if [ "$arg" = -m ]
            set expect_model 1
        else if string match -qr '^-[a-z]+$' -- $arg
            # bundled short flags: extract -o (opus) / -f (fable), pass the rest back to claude
            if string match -q '*o*' -- $arg
                set model opus
                set arg (string replace -a o '' -- $arg)
            end
            if string match -q '*f*' -- $arg
                set model claude-fable-5
                set arg (string replace -a f '' -- $arg)
            end
            if [ "$arg" != - ]
                set -a passthrough_args $arg
            end
        else
            set -a passthrough_args $arg
        end
        #TODO: add `-p` for opening in plan mode over a specific file
    end

    set -l pwd (pwd -P)
    for proj in $utmost_importance_projects
        set -l proj_real (realpath -m -- $proj)
        if [ "$pwd" = "$proj_real" ] || string match -q -- "$proj_real/*" "$pwd"
            if [ "$model" = opus ]
                echo "cl: '$proj' is an utmost-importance project — opus is refused here." >&2
                echo "    Run on fable (cl -f) or remove '$proj' from utmost_importance_projects in llm.fish." >&2
                return 1
            end
            if [ -z "$model" ]
                set model claude-fable-5
            end
            break
        end
    end

    if [ -n "$model" ]
        set -a passthrough_args --model $model
    end

    if [ $expect_model -eq 1 ]
        echo "cl: -m requires a model argument" >&2
        return 1
    end

    if set -q resume_n[1]
        if [ $resume_n -eq 1 ]
            set -a passthrough_args --continue
        else
            set -l proj_dir $HOME/.claude/projects/(string replace -ra '[^a-zA-Z0-9]' - -- (pwd -P))
            set -l sessions (command ls -t $proj_dir/*.jsonl 2>/dev/null)
            if [ (count $sessions) -lt $resume_n ]
                echo "cl: only "(count $sessions)" session(s) recorded for this directory" >&2
                return 1
            end
            set -a passthrough_args --resume (basename $sessions[$resume_n] .jsonl)
        end
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

    # not `command`: routes through the claude function above so `cl -a 2` works
    # `string collect`: without it fish splits the file on newlines into one argument each
    $base_cmd --append-system-prompt (cat $HOME/.claude/daneel.md | string collect) $passthrough_args
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

function clr
    cl review $argv
end
