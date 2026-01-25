# Sierra Chart trading platform via Wine
# Downloads on first run since their server has SSL cert issues that break fetchurl
final: prev: {
  sierra-chart = prev.writeShellApplication {
    name = "sierra-chart";
    runtimeInputs = with prev; [
      wineWowPackages.waylandFull
      winetricks
      curl
      unzip
      coreutils
      sway
      jq
    ];
    text = ''
      set -euo pipefail

      WINEPREFIX="$HOME/.wine-sierrachart"
      WINEARCH=win64
      export WINEPREFIX WINEARCH

      SC_DIR="$WINEPREFIX/drive_c/SierraChart"
      SC_VERSION="2867"
      SC_ZIP_URL="https://download2.sierrachart.com/downloads/ZipFiles/SierraChart''${SC_VERSION}.zip"

      # Download and extract if not present
      if [ ! -f "$SC_DIR/SierraChart_64.exe" ]; then
          echo "Sierra Chart not found. Setting up..."

          # Initialize Wine prefix
          if [ ! -d "$WINEPREFIX" ]; then
              echo "Initializing Wine prefix at $WINEPREFIX..."
              wineboot --init
              echo "Installing fonts..."
              winetricks -q corefonts
          fi

          # Download Sierra Chart
          echo "Downloading Sierra Chart v$SC_VERSION..."
          mkdir -p "$SC_DIR"
          TMP_ZIP=$(mktemp --suffix=.zip)
          curl -kL -o "$TMP_ZIP" "$SC_ZIP_URL"

          echo "Extracting..."
          unzip -o "$TMP_ZIP" -d "$SC_DIR"
          rm "$TMP_ZIP"

          echo ""
          echo "=== IMPORTANT: After Sierra Chart starts ==="
          echo "Go to: Global Settings → Sierra Chart Server Settings → General → Special"
          echo "Set 'Use Single Network Receive Buffer for Linux Compatibility' to YES"
          echo "============================================="
          echo ""
      fi

      # Wine cursor fix: temporarily move all outputs to 0 0
      # Save current output positions and reset to 0 0
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

      wine "$SC_DIR/SierraChart_64.exe" "$@"
    '';
  };
}
