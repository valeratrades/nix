#!/usr/bin/env bash
# PreToolUse(Bash): commands that outlive their purpose. CC runs each command as `bash -c '<the whole command>'`, and a
# foreground one past its timeout is moved to the background, not killed: a loop whose condition never comes true
# then runs until the session ends, and the session reads as busy.
cmd=$(jq -r '.tool_input.command // empty')
# the shell's own argv holds the pattern, so `-f` always matches (pgrep) or kills (pkill) the very shell asking
if grep -qE '(^|[;&|({`!]|\$\(|\b(then|do|else|xargs|sudo|timeout [0-9a-z.]+))[[:space:]]*p(grep|kill)[[:space:]]([^|;&]*[[:space:]])?-[a-zA-Z]*f' <<<"$cmd"; then
	echo "Blocked: \`pgrep -f\`/\`pkill -f\` match this command's own shell, whose argv holds the pattern. Use the PID (\$!, a background task's id), \`pgrep -x <name>\`, \`ss -ltnp\` for a port, or \`kill -- -<pgid>\`." >&2
	exit 2
fi
# a polling loop must end by itself whatever it waits for
if grep -qE '\b(until|while)\b' <<<"$cmd" && grep -qE '\bsleep\b' <<<"$cmd" && ! grep -qE '\btimeout[[:space:]]+[0-9]' <<<"$cmd"; then
	echo "Blocked: a polling loop with no bound. Wrap it: \`timeout <secs> bash -c 'until …; do sleep …; done'\`. Better: wait on what the waited command itself writes (\`cmd; echo DONE >> log\`), on its PID (\`tail --pid=<pid> -f /dev/null\`), or on run_in_background's notification." >&2
	exit 2
fi
