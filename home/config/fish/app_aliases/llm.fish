alias claude_all "claude --dangerously-skip-permissions"
complete -c claude_all -w claude
#alias cl="claude_all"
alias cl="claude_all --model claude-sonnet-4-6" #NB: keep `--model` up-to-date and comment out entirely when my model of choice matches default
complete -c cl -w claude
