#!/bin/sh
# Toggle an OBS filter via obs-websocket.
# Usage: obs_filter_toggle.sh <source-name> <filter-name>
# Reads port + password from OBS's plugin_config so we don't have to manage them separately.
set -eu

src=${1:?source name required}
filt=${2:?filter name required}

cfg="$HOME/.config/obs-studio/plugin_config/obs-websocket/config.json"
port=$(jq -r '.server_port' "$cfg")
pw=$(jq -r '.server_password' "$cfg")

exec obs-cmd -w "obsws://localhost:${port}/${pw}" filter toggle "$src" "$filt"
