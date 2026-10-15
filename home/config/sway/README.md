## workspaces:
Workspace | Uses
--- | ---
1 | work tmux sessions
2 | browser
3 | notes / todo
4 | messengers / music
5 | reading
6 | ssh
7 | trading terminal
8 | obs
9 | whiteboard
0 | tmp (monitoring logs)

## outputs
Laptop panel is `$output_laptop = "eDP-1" "eDP-2"`; position, dpms and workspace rules match whichever exists.
The number isn't stable: on hybrid-GPU laptops both drivers expose an `eDP` connector, and the kernel numbers them in driver probe order, which races per boot (nvidia first → panel on amdgpu becomes `eDP-2`).

Symptom when it misses: laptop placed to the right of the monitor instead of below it, ws 4/5/8/9 on the wrong screen.
Check: `swaymsg -t get_outputs | jq -r '.[].name'`, or `ls /sys/class/drm/` for connectors per card.
Fix: add the new name everywhere `eDP-2` appears in `config` (`output` takes one name, so those lines are duplicated per name). Old laptops may use `LVDS-1`.
