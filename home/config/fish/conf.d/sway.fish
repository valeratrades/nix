set TTY1 (tty)
# -d + redirect: sway's startup/DRM/renderer errors go to a persistent file instead of
# vanishing on tty1, so a failed boot is diagnosable from the rollback (journal never sees it).
[ "$TTY1" = "/dev/tty1" ] && exec sway -d 2>$HOME/.sway.log
