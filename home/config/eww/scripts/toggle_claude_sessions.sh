#!/bin/sh

claude_sessions_always_expand=$(eww --no-daemonize get claude_sessions_always_expand) || exit 0
if [ "$claude_sessions_always_expand" = "true" ]; then
  eww --no-daemonize update claude_sessions_always_expand="false"
else
  eww --no-daemonize update claude_sessions_always_expand="true"
fi
