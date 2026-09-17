#!/bin/sh
# --no-daemonize: with the bar deliberately down, a plain client call forks a window-less
# daemon that then owns the socket, which is how the toggle stopped reaching the real bar.

bar_visible=$(eww --no-daemonize get bar_visible) || exit 0
if [ "$bar_visible" = "true" ]; then
  eww --no-daemonize update bar_visible="false"
else
  eww --no-daemonize update bar_visible="true"
fi
