# Ctrl+Z backgrounds the job instead of leaving it stopped. A job catching SIGTSTP or SIGWINCH (nvim, less) owns the terminal and would repaint over the prompt, so it stays stopped.
function __stopped_jobs # "<job id> <group>", most recent first
    jobs | string replace -rf '^(\d+)\t(\d+)\t[^\t]*\tstopped\t.*' '$1 $2'
end
function __remember_stopped --on-event fish_preexec
    set -g __stopped_before (__stopped_jobs | string split -f2 ' ')
end
function __bg_on_suspend --on-event fish_postexec
    set -l job (__stopped_jobs)[1]
    test -n "$job"; or return
    set job (string split ' ' $job)
    contains $job[2] $__stopped_before; and return # stopped before this command ran
    for pid in (jobs --pid %$job[1])
        set -l mask (string match -rg '^SigCgt:\s*(\S+)' </proc/$pid/status | string sub -s -8)
        test (math "bitand(0x$mask, 0x8080000)") -ne 0; and return
    end
    bg %$job[1]
end
# the plain stop, for the job Ctrl+Z just backgrounded
bind ctrl-Z 'jobs -q; and kill -STOP -- -(jobs --last --group); commandline -f repaint'
