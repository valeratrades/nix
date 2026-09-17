# eww: the visibility toggle silently stops working

Symptom as reported: `pkill eww` revives instantly, and the sway hide/show shortcut
($mod+Shift+e, or $mod+e → h) no longer hides the bar — at most the btc_line rows go away.

## Mechanism (confirmed, not theorised)

Any eww *client* command that finds no socket forks its own daemon. `--no-daemonize` is
the flag that turns that into a clean `Failed to connect to daemon` instead.

The unit's `ExecStartPost` ran `eww open-many …` **without** it. Sequence:

```
pkill eww            daemon dies, socket gone
  └─ Restart=always → ExecStart: `eww daemon --restart` (pid A) binds socket
     └─ ExecStartPost: `eww open-many …` → socket momentarily absent → forks pid B
                                            B binds the socket AND opens the windows
```

Result: **two daemons**. `pgrep` hides this — B's argv stays `eww open-many …`, so it
does not look like a daemon. Verified by `ls /proc/<pid>/fd`: both held wayland + server
sockets, and killing B left A alive but unreachable (`eww get` → "Failed to connect").

Whichever daemon owns the socket receives `eww update bar_visible=…`; the other owns the
windows you can see. So the toggle flips a variable in a bar nobody is looking at.

The `until eww ping --no-daemonize` loop that preceded the open was a TOCTOU — ping proves
the socket existed a moment ago, not that the next connect finds it.

## Fix (d-, this commit)

- `ExecStartPost`: `until eww --no-daemonize open-many $(cat eww_windows.txt); do sleep 0.1; done`
  — retrying the real call *is* the readiness check, and it can no longer fork a rival.
- `Restart=always` → `on-failure`. eww exits 0 on SIGTERM and systemd counts SIGTERM as a
  clean exit, so `pkill eww` now stays dead while a real crash (status=1, SIGKILL) still
  comes back. `eww_open` restarts it by hand.
- `--no-daemonize` on every other client call: both toggle scripts, the 8 `eww update
  sway_mode=` bindings in sway/config, and `eww_open_on.rs`. With a deliberately-killed
  bar, an unguarded call would otherwise leave a window-less zombie holding the socket.
- `$switch_out` gained `|| true`: it is chained with `&&` into the actual action, and a
  now-failing update would swallow it.

## Ruled out along the way

- **sway not substituting `$switch_out` in `mode "eww"` (defined at line 298, used at 272).**
  Looked like a second bug; it is not. sway substitutes at command-execution time, not at
  parse time. Verified by driving the real binding with `wtype h` — `bar_visible` flipped.
- **btc_line.service forking rivals via its `eww update` output.** Stopped the unit and
  waited out several update cycles with eww down: no daemon appeared.
- **GTK `:visible` on the window's child box being unreliable.** It works; every hide test
  against a single daemon hid the bar, btc_line rows, tedi_blocker and claude_sessions.

## Regression test (manual, ~40s)

```sh
for i in 1 2 3; do
  kill -9 $(pgrep -f 'eww daemon'); sleep 0.7
  ~/.config/sway/eww_visibility_toggle.sh; sleep 0.7
  ~/.config/sway/eww_visibility_toggle.sh; sleep 3
done
sleep 6; pgrep -a eww   # must print exactly one line
```

Then `swaymsg 'mode "eww"' && wtype h` and screenshot with
`grim -g "1400,1080 1160x120"` — the bar must actually disappear.
