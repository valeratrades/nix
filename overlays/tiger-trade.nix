# Tiger Trade terminal via Wine. A .NET 10 WPF app: runtime from Microsoft's zips, Direct3D through DXVK (Wine's own GL path fails to init on the hybrid AMD+NVIDIA laptop and the app hangs).
final: prev:
let
  wineApp = prev.callPackage ./wine-wrapper.nix {};
  version = "7.4.9792.30944";
  setup = prev.fetchurl {
    url = "https://cdn-gl.tiger.trade/download/release/TigerTradeSetup_${version}.exe";
    hash = "sha256-+SkVX1Aa3SUaVKu/I1bp3fXUxShU4miUy6PG4kIGMTs=";
  };
  # WiX Burn bundle: its last cabinet holds the MSI, unpacked here so no installer GUI ever runs
  app = prev.runCommand "tiger-trade-${version}" { nativeBuildInputs = with prev; [ python3 cabextract msitools ]; } ''
    off=$(python3 -c 'import sys; print(open(sys.argv[1], "rb").read().rindex(b"MSCF\0\0\0\0"))' ${setup})
    tail -c +$((off + 1)) ${setup} > bundle.cab
    cabextract -q bundle.cab
    msiextract -C msi a0
    mv "msi/Program Files/TigerTrade" $out
  '';
  dotnetVersion = "10.0.14"; # TigerTrade.runtimeconfig.json: NETCore + WindowsDesktop + AspNetCore 10.0
  dotnet = prev.runCommand "dotnet-runtime-${dotnetVersion}-win-x64" { nativeBuildInputs = [ prev.unzip ]; } ''
    mkdir $out
    unzip -qo ${prev.fetchurl {
      url = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/${dotnetVersion}/windowsdesktop-runtime-${dotnetVersion}-win-x64.zip";
      hash = "sha256-rP3D9GTsO9dGnNrNvGlYQu/ST/PlFNL8KDeJAr4pMcw=";
    }} -d $out
    unzip -qo ${prev.fetchurl {
      url = "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/${dotnetVersion}/aspnetcore-runtime-${dotnetVersion}-win-x64.zip";
      hash = "sha256-rmHNTbZTxP7JtK10/IvbLXNReZZtQA/f5kxl8bNsIBQ=";
    }} -d $out
  '';
in {
  tiger-trade = wineApp {
    name = "tiger-trade";
    x11 = true;
    winePrefix = "$HOME/.wine-tigertrade";
    setupScript = ''
      TT_DIR="$WINEPREFIX/drive_c/TigerTrade"
      if [ ! -d "$WINEPREFIX" ]; then
          WINEDLLOVERRIDES="mscoree,mshtml=" wineboot --init # skips the Mono/Gecko install prompts
      fi
      if ! cmp -s "${app}/TigerTrade.exe" "$TT_DIR/TigerTrade.exe"; then # first run or version bump
          rm -rf "$TT_DIR"
          cp -r --no-preserve=mode "${app}" "$TT_DIR"
      fi
      cp --no-preserve=mode ${prev.dxvk.bin}/x64/*.dll "$WINEPREFIX/drive_c/windows/system32/"
      cp --no-preserve=mode ${prev.dxvk.bin}/x32/*.dll "$WINEPREFIX/drive_c/windows/syswow64/"
      export WINEDLLOVERRIDES="d3d8,d3d9,d3d10core,d3d11,dxgi=n,b;mshtml=" # mscoree stays builtin: CoreCLR needs it to load IL-only assemblies
      export DOTNET_ROOT="Z:${builtins.replaceStrings [ "/" ] [ "\\" ] "${dotnet}"}"
    '';
    runCmd = ''wine "$WINEPREFIX/drive_c/TigerTrade/TigerTrade.exe" "$@"'';
  };
}
