# CoinPoker (Electron) via Wine. Unpacks the NSIS payload directly: no installer GUI, no registry needed.
final: prev:
let
  wineApp = prev.callPackage ./wine-wrapper.nix {};
in {
  coinpoker = wineApp {
    name = "coinpoker";
    x11 = true;
    winePrefix = "$HOME/.wine-coinpoker";
    runtimeInputs = [ prev.p7zip ];
    setupScript = ''
      export WINEDLLOVERRIDES="mscoree,mshtml="
      CP_DIR="$WINEPREFIX/drive_c/CoinPoker"
      CP_URL="https://d26s3bt6yeixto.cloudfront.net/source/CoinPoker-release-win-x64.exe"

      if [ ! -f "$CP_DIR/CoinPoker.exe" ]; then
          if [ ! -d "$WINEPREFIX" ]; then
              wineboot --init
          fi

          WORK=$(mktemp -d -p "$HOME/.cache")
          curl -L -o "$WORK/setup.exe" "$CP_URL"
          # shellcheck disable=SC2016
          7z e -o"$WORK" "$WORK/setup.exe" '$PLUGINSDIR/app-64.7z' -y
          mkdir -p "$CP_DIR"
          7z x -o"$CP_DIR" "$WORK/app-64.7z" -y
          rm -rf "$WORK"
      fi
    '';
    runCmd = ''wine "$WINEPREFIX/drive_c/CoinPoker/CoinPoker.exe" --no-sandbox "$@"'';
  };
}
