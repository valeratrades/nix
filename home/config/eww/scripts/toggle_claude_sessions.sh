#!/bin/sh

claude_sessions_always_expand=$(eww get claude_sessions_always_expand)
if [ "$claude_sessions_always_expand" = "true" ]; then
  eww update claude_sessions_always_expand="false"
else
  eww update claude_sessions_always_expand="true"
fi
