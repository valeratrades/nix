# Shared Wine wrapper for Sway - fixes cursor by temporarily resetting monitor positions
# Usage: wineApp { name, winePrefix, setupScript, runCmd, runtimeInputs ? [] }
{ lib, writeShellApplication, wineWowPackages, winetricks, curl, unzip, coreutils, sway, jq }:

{ name, winePrefix, setupScript ? "", runCmd, runtimeInputs ? [] }:

writeShellApplication {
  inherit name;
  runtimeInputs = [
    wineWowPackages.waylandFull
    winetricks
    curl
    unzip
    coreutils
    sway
    jq
  ] ++ runtimeInputs;
  text = ''
    set -euo pipefail

    WINEPREFIX="${winePrefix}"
    WINEARCH=win64
    export WINEPREFIX WINEARCH

    # Wine cursor fix: temporarily move all outputs to 0 0
    # Must happen BEFORE any wine commands (including setup)
    SAVED_OUTPUTS=$(swaymsg -t get_outputs | jq -r '.[] | "\(.name) \(.rect.x) \(.rect.y)"')

    cleanup() {
        echo "Restoring monitor positions..."
        while IFS=' ' read -r name x y; do
            swaymsg output "$name" pos "$x" "$y" 2>/dev/null || true
        done <<< "$SAVED_OUTPUTS"
    }
    trap cleanup EXIT

    echo "Temporarily resetting monitor positions for Wine compatibility..."
    swaymsg -t get_outputs | jq -r '.[].name' | while read -r name; do
        swaymsg output "$name" pos 0 0 2>/dev/null || true
    done

    # Run setup if needed
    ${setupScript}

    # Run the app
    ${runCmd}
  '';
}
