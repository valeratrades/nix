# dirs where fable is forced and opus is refused; matches the dir itself and anything under it
set -g utmost_importance_projects $HOME/ev_invest/trading_data $HOME/ev_invest/risk_management

# Accounts are logins only, in ~/.claude/accounts/N; all else is the one ~/.claude. Every claude runs on the one
# `current` links, following `cl rotate-acc` and the rate-limit menu in place (hosts/v-laptop/claude-accounts.mjs).
# `env -u`: credentials.fish exports both session-wide, and either outranks the account's login --
# ANTHROPIC_API_KEY bills as API credits, CLAUDE_CODE_OAUTH_TOKEN pins every claude to its one account
# and lacks the scopes claude.ai connectors need.
function claude
    if [ "$TERM_PROGRAM" = ghostty ]; or begin; set -q TMUX; and [ (tmux display -p '#{client_termname}') = xterm-ghostty ]; end
        echo "claude: ghostty eats alt+g / alt+shift+g (its scroll_to_top/bottom), so claude's scroll top/bottom won't fire" >&2
    end
    set -fx CLAUDE_SECURESTORAGE_CONFIG_DIR (path resolve $HOME/.claude/accounts/current)
    if not test -d $CLAUDE_SECURESTORAGE_CONFIG_DIR
        echo "claude: ~/.claude/accounts/current names no account dir (`cl rotate-acc` sets it)" >&2
        return 1
    end
    # background.slice (CPUWeight=30): agents' builds otherwise share the tmux cgroup with interactive shells and starve them
    systemd-run --user --scope --quiet --slice=background.slice env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN claude $argv
end

function cl
    if [ "$argv[1]" = rotate-acc ]
        set -l root $HOME/.claude/accounts
        set -l acc $argv[2]
        if [ -z "$acc" ]
            set -l rows
            for d in $root/*
                set -l name (path basename -- $d)
                if [ $name = current ]; or [ (path resolve -- $d) = (path resolve -- $root/current) ]
                    continue
                end
                set -l label "not logged in"
                if test -f $d/meta.json
                    # same reading as the rate-limit menu's entries
                    set label (jq -r '[.email,
                        ([["5h", .usage.five_hour], ["week", .usage.seven_day]] | map(select(.[1]) | .[1] as $w
                            | "\(.[0]) \(if $w.resets_at and ($w.resets_at[0:19] + "Z" | fromdateiso8601) <= now then 100 else 100 - $w.utilization | round end)% left")
                            | join(" · ")),
                        "as of \(.fetchedAt / 1000 | localtime | strftime("%H:%M"))"] | join(" · ")' $d/meta.json)
                    or return 1
                else if test -f $d/.credentials.json
                    set label "usage unknown"
                end
                set -a rows "$name	$label"
            end
            if not set -q rows[1]
                echo "cl rotate-acc: no account besides the current one in $root" >&2
                return 1
            end
            set acc (printf '%s\n' $rows | fzf --delimiter \t --prompt 'account> ' | string split -f1 \t)
            or return 1
        end
        if not test -d $root/$acc
            echo "cl rotate-acc: no $root/$acc (mkdir it to add an account)" >&2
            return 1
        end
        ln -s $acc $root/current.$fish_pid; and mv -T $root/current.$fish_pid $root/current
        or return 1
        if not test -f $root/$acc/.credentials.json
            echo "cl rotate-acc: account $acc has no login yet: running claudes stay where they are; /login in a new one adds it" >&2
        end
        return
    end
    if [ "$argv[1]" = review ]
        # `-f` here selects by hand rather than picking fable; `cl review -m claude-fable-5-1` still works
        set -l pick_args
        set -l rest
        for arg in $argv[2..]
            if [ "$arg" = -f ] || [ "$arg" = --fuzzy ]
                set -a pick_args --fuzzy
            else
                set -a rest $arg
            end
        end
        # picker echoes its own choice to stderr
        set -l prompt ($HOME/s/codestyle/skills/pick.rs (pwd -P) $pick_args | string collect)
        if [ -z "$prompt" ]
            return 1
        end
        cl $prompt $rest
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
            # bundled short flags: extract the model letters, pass the rest back to claude.
            # s/t/l are litellm groups (mixed.yaml, openai.yaml) -- only resolve under clm/clc.
            for pair in o:opus f:claude-fable-5-1 s:sol t:terra l:luna
                set -l letter (string split -f1 : -- $pair)
                if string match -q "*$letter*" -- $arg
                    set model (string split -f2 : -- $pair)
                    set arg (string replace -a $letter '' -- $arg)
                end
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
                set model claude-fable-5-1
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

function clc
    # for `CLaude Cheap`

    function use_deepseek
        set -lx ANTHROPIC_BASE_URL 'https://api.deepseek.com/anthropic'
        set -lx ANTHROPIC_AUTH_TOKEN "$DEEPSEEK_API_KEY"
        set -lx ANTHROPIC_MODEL 'deepseek-v4-pro[1m]'
        set -lx ANTHROPIC_DEFAULT_SONNET_MODEL 'deepseek-v4-pro[1m]'
        set -lx ANTHROPIC_DEFAULT_OPUS_MODEL 'deepseek-v4-pro[1m]'
        set -lx ANTHROPIC_DEFAULT_HAIKU_MODEL 'deepseek-v4-flash[1m]'
        
        cl $argv
    end

    function use_openai
        # chosen in vars/ports.nix, exported by os/nixos/desktop/environment.nix
        if not set -q LITELLM_PORT
            echo "clc: LITELLM_PORT unset -- stale session, or environment.nix no longer exports it" >&2
            return 1
        end
        set -lx ANTHROPIC_BASE_URL "http://127.0.0.1:$LITELLM_PORT"
        set -lx ANTHROPIC_AUTH_TOKEN 'local'

        # Names are litellm *model groups* (openai.yaml), not upstream model ids: the proxy 400s
        # on `gpt-5.6-terra`.
        set -lx ANTHROPIC_MODEL 'terra'

        # Map Claude's three tiers onto the 5.6 family.
        set -lx ANTHROPIC_DEFAULT_OPUS_MODEL 'sol'
        set -lx ANTHROPIC_DEFAULT_SONNET_MODEL 'terra'
        set -lx ANTHROPIC_DEFAULT_HAIKU_MODEL 'luna'

        cl $argv
    end

    use_openai $argv
end

function clm
    # for `CLaude Mixed` -- Opus driving the session, Luna as the subagent tier.
    # Claude Code resolves one ANTHROPIC_BASE_URL per process, so both providers have to sit behind
    # one litellm. The cost: Opus authenticates by API key here, off the Max subscription.
    # Own port and own config, so `clc` and openclaw keep their proxy to themselves.
    # Both ports are chosen in vars/ports.nix, exported by os/nixos/desktop/environment.nix.
    if not set -q LITELLM_MIXED_PORT
        echo "clm: LITELLM_MIXED_PORT unset -- stale session, or environment.nix no longer exports it" >&2
        return 1
    end
    set -l health "http://127.0.0.1:$LITELLM_MIXED_PORT/health/liveliness"
    if not curl -sf -m 2 $health >/dev/null 2>&1
        litellm --config $NIXOS_CONFIG/home/config/litellm/mixed.yaml --port $LITELLM_MIXED_PORT >/tmp/litellm-mixed.log 2>&1 &
        disown
        for i in (seq 40)
            curl -sf -m 1 $health >/dev/null 2>&1; and break
            sleep 1
        end
        if not curl -sf -m 2 $health >/dev/null 2>&1
            echo "clm: mixed litellm never came up on :$LITELLM_MIXED_PORT; see /tmp/litellm-mixed.log" >&2
            return 1
        end
    end

    # These three pick the defaults only; mixed.yaml registers more (sonnet, fable, haiku, sol,
    # pro), each reachable as `clm -m <group>`.
    set -lx ANTHROPIC_BASE_URL "http://127.0.0.1:$LITELLM_MIXED_PORT"
    set -lx ANTHROPIC_AUTH_TOKEN 'local'
    set -lx ANTHROPIC_MODEL 'opus'
    set -lx ANTHROPIC_DEFAULT_OPUS_MODEL 'opus'
    set -lx ANTHROPIC_DEFAULT_SONNET_MODEL 'terra'
    set -lx ANTHROPIC_DEFAULT_HAIKU_MODEL 'luna'

    cl $argv
end

function clp
    cl --permission-mode plan "Plan file: $argv[1]. Select it and submit for approval (approval, - do not start execution)" $argv[2..]
end

function clr
    cl review $argv
end
