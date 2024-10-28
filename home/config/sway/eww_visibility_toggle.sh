#!/bin/sh

bar_visible=$(eww get bar_visible)
if [ "$bar_visible" = "true" ]; then
  eww update bar_visible="false"
else
  eww update bar_visible="true"
fi

