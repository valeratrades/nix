# Tiger Trade terminal via Wine
# Requires .NET Framework 4.7.2+ which is installed on first run
final: prev: {
  tiger-trade = prev.writeShellApplication {
    name = "tiger-trade";
    runtimeInputs = with prev; [
      wineWowPackages.waylandFull
      winetricks
      curl
      coreutils
      sway
      jq
    ];
    text = ''
      set -euo pipefail

      WINEPREFIX="$HOME/.wine-tigertrade"
      WINEARCH=win64
      export WINEPREFIX WINEARCH

      TT_DIR="$WINEPREFIX/drive_c/Program Files/TigerTrade"
      TT_VERSION="7.1"
      TT_INSTALLER_URL="https://storage.googleapis.com/tiger-trade-site-content-cdn-production/download/TigerTradeSetup_''${TT_VERSION}.exe"

      # Check if already installed
      if [ ! -f "$TT_DIR/TigerTrade.exe" ]; then
          echo "Tiger Trade not found. Setting up..."

          # Initialize Wine prefix
          if [ ! -d "$WINEPREFIX" ]; then
              echo "Initializing Wine prefix at $WINEPREFIX..."
              wineboot --init

              echo "Installing fonts..."
              winetricks -q corefonts

              echo ""
              echo "Installing .NET Framework 4.7.2 (this takes a while)..."
              echo "You may see Windows installer dialogs - follow any prompts."
              echo ""
              winetricks -q dotnet472

              echo ".NET installation complete."
          fi

          # Download Tiger Trade installer
          echo "Downloading Tiger Trade v$TT_VERSION..."
          TMP_INSTALLER=$(mktemp --suffix=.exe)
          curl -L -o "$TMP_INSTALLER" "$TT_INSTALLER_URL"

          echo ""
          echo "Running installer..."
          echo "Follow the installation wizard. Default install path is recommended."
          echo ""
          wine "$TMP_INSTALLER"
          rm "$TMP_INSTALLER"

          if [ ! -f "$TT_DIR/TigerTrade.exe" ]; then
              echo ""
              echo "WARNING: TigerTrade.exe not found at expected location."
              echo "If you installed to a different path, edit this script or run manually:"
              printf '  WINEPREFIX=%s wine "C:\\path\\to\\TigerTrade.exe"\n' "$WINEPREFIX"
              exit 1
          fi
      fi

      # Wine cursor fix: temporarily move all outputs to 0 0
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

      wine "$TT_DIR/TigerTrade.exe" "$@"
    '';
  };
}
