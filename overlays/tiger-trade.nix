# Tiger Trade terminal via Wine
# Requires .NET Framework 4.7.2+ which is installed on first run
final: prev:
let
  wineApp = prev.callPackage ./wine-wrapper.nix {};
in {
  tiger-trade = wineApp {
    name = "tiger-trade";
    winePrefix = "$HOME/.wine-tigertrade";
    setupScript = ''
      TT_DIR="$WINEPREFIX/drive_c/Program Files/TigerTrade"
      TT_VERSION="7.1"
      TT_INSTALLER_URL="https://storage.googleapis.com/tiger-trade-site-content-cdn-production/download/TigerTradeSetup_''${TT_VERSION}.exe"

      if [ ! -f "$TT_DIR/TigerTrade.exe" ]; then
          echo "Tiger Trade not found. Setting up..."

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
    '';
    runCmd = ''wine "$WINEPREFIX/drive_c/Program Files/TigerTrade/TigerTrade.exe" "$@"'';
  };
}
