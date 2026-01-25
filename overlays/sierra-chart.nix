# Sierra Chart trading platform via Wine
final: prev:
let
  wineApp = prev.callPackage ./wine-wrapper.nix {};
in {
  sierra-chart = wineApp {
    name = "sierra-chart";
    winePrefix = "$HOME/.wine-sierrachart";
    setupScript = ''
      SC_DIR="$WINEPREFIX/drive_c/SierraChart"
      SC_VERSION="2867"
      SC_ZIP_URL="https://download2.sierrachart.com/downloads/ZipFiles/SierraChart''${SC_VERSION}.zip"

      if [ ! -f "$SC_DIR/SierraChart_64.exe" ]; then
          echo "Sierra Chart not found. Setting up..."

          if [ ! -d "$WINEPREFIX" ]; then
              echo "Initializing Wine prefix at $WINEPREFIX..."
              wineboot --init
              echo "Installing fonts..."
              winetricks -q corefonts
          fi

          echo "Downloading Sierra Chart v$SC_VERSION..."
          mkdir -p "$SC_DIR"
          TMP_ZIP=$(mktemp --suffix=.zip)
          curl -kL -o "$TMP_ZIP" "$SC_ZIP_URL"

          echo "Extracting..."
          unzip -o "$TMP_ZIP" -d "$SC_DIR"
          rm "$TMP_ZIP"

          echo ""
          echo "=== IMPORTANT: After Sierra Chart starts ==="
          echo "Go to: Global Settings -> Sierra Chart Server Settings -> General -> Special"
          echo "Set 'Use Single Network Receive Buffer for Linux Compatibility' to YES"
          echo "============================================="
          echo ""
      fi
    '';
    runCmd = ''wine "$WINEPREFIX/drive_c/SierraChart/SierraChart_64.exe" "$@"'';
  };
}
