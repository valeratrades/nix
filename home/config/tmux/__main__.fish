# tmux panes outlive a sway restart, keeping SWAYSOCK of the dead compositor
function __swaysock_refresh --on-event fish_preexec
    set -q SWAYSOCK; and not test -S $SWAYSOCK; or return
    for sock in $XDG_RUNTIME_DIR/sway-ipc.*.sock
        test -d /proc/(string split . -- $sock)[-2]; or continue # a crashed sway leaves its socket behind
        set -gx SWAYSOCK $sock
        return
    end
end
