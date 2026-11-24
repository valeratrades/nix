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
# a dev server mid-build accepts the connection and answers nothing
if grep -qE '\bcurl\b[^|;&]*(localhost|127\.0\.0\.1)' <<<"$cmd" && ! grep -qE '(^|[[:space:]])(-[a-zA-Z]*m[[:space:]]*[0-9]|--max-time)|\btimeout[[:space:]]+[0-9]' <<<"$cmd"; then
	echo "Blocked: \`curl\` to a local server with no \`-m <secs>\`: one mid-build accepts and never answers." >&2
	exit 2
fi
# a multi-line command's stdin is an open socket, and `rg` with no path reads stdin whenever it is neither a tty nor /dev/null
if [[ $cmd == *$'\n'* ]] && grep -qE '\brg\b' <<<"$cmd" && ! python3 -c '
import shlex, sys
lex = shlex.shlex(sys.argv[1], posix=True, punctuation_chars="();<>|&\n")
lex.whitespace, lex.commenters, lex.whitespace_split = " \t\r", "", True
try:
    words = list(lex)
except ValueError:
    sys.exit(0)  # quotes only bash can read: not judged
op = lambda w: w.strip("();<>|&\n") == ""
valued = {"-g", "-t", "-T", "-A", "-B", "-C", "-m", "-r", "-M", "-j", "-E", "-d", "--glob", "--type", "--max-depth", "--max-count", "--replace"}
for i, w in enumerate(words):
    if w != "rg" or (i and (not op(words[i - 1]) or words[i - 1] == "|")):
        continue
    args = []
    for a in words[i + 1:]:
        if op(a):
            if a.startswith("<"):
                args += ["", ""]
            break
        args.append(a)
    paths, skip, need = 0, False, 2
    for a in args:
        if skip:
            skip = False
        elif a in ("-e", "-f", "--regexp", "--file"):
            skip, need = True, 1
        elif a in valued:
            skip = True
        elif a in ("--files", "--type-list", "--version", "--help"):
            need = 1 if a == "--files" else 0
        elif not a.startswith("-"):
            paths += 1
    if paths < need:
        sys.exit(1)
' "$cmd"; then
	echo "Blocked: \`rg\` with no path in a multi-line command waits on stdin forever. Name the path: \`rg PATTERN .\`." >&2
	exit 2
fi
