#!/bin/sh
# window geometry only reads window args, so a zoom change needs the windows reopened

zoom=$(eww --no-daemonize get zoom) || exit 0
eww --no-daemonize update zoom=$((3 - zoom))
exec "$NIXOS_CONFIG/home/scripts/eww_open_on.rs" focused
