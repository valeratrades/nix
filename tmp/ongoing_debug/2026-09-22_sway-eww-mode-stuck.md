# Sway eww mode can trap keyboard input

## Problem

Entering the eww mode-selection menu (`$mod+e`) can leave sway in mode `eww`; Escape and the listed choices then do nothing. Reloading sway is required to recover. This has recurred.

## Root cause (confirmed from current config and commit history)

The shared `$switch_out` command was removed from `home/config/sway/config` by `a7629dcd` while the mode blocks continued to reference it. The eww block therefore contained bindings such as `bindsym Escape exec $switch_out` with an undefined variable. Sway accepted the configuration, but the expanded command was empty, so Escape did not issue `swaymsg mode default`. The same defect affected every mode using that shared exit binding.

The preceding commit message claimed the variable had been moved before mode blocks, but the committed diff shows only its removal from the old location and no replacement. That explains why the problem returned after the earlier fix.

## Fix

Define `$switch_out` before all mode blocks. Its first operation is always `swaymsg mode default`; eww state cleanup is best-effort and cannot prevent mode cancellation. This makes Escape independent of eww daemon availability and prevents a missing eww socket from trapping sway in a mode.

## Verification

Validate the generated sway configuration and assert that `$switch_out` is defined before `mode "eww"`, with an Escape binding present in that mode. When a live sway session is available, enter `eww` and press Escape; expected state is `mode default` even if eww is stopped.
