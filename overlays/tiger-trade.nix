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
  # System.Management (the app's hardware info, which feeds its HardwareID) needs these natives from a .NET Framework install: <InstallRoot>\v4.0.30319\wminet_utils.dll plus the CLR's private CRT in system32
  netfx = prev.runCommand "netfx48-wminet-utils" { nativeBuildInputs = with prev; [ p7zip cabextract ]; } ''
    7z e -y ${prev.fetchurl {
      url = "https://download.microsoft.com/download/f/3/a/f3a6af84-da23-40a5-8d1c-49cc10c8e76f/NDP48-x86-x64-AllOS-ENU.exe";
      hash = "sha256-Cjo5DEfmOdD3/GWyEZX+5rf2WwZvgPcMYPqxkdFLfkA=";
    }} netfx_Full.mzz > /dev/null
    cabextract -q -F wminet_utils_dll_amd64 -F ucrtbase_clr0400_dll_amd64 -F vcruntime140_clr0400_dll_amd64 netfx_Full.mzz
    install -Dm444 wminet_utils_dll_amd64 $out/v4.0.30319/wminet_utils.dll
    install -Dm444 ucrtbase_clr0400_dll_amd64 $out/system32/ucrtbase_clr0400.dll
    install -Dm444 vcruntime140_clr0400_dll_amd64 $out/system32/vcruntime140_clr0400.dll
  '';
  winPath = p: "Z:${builtins.replaceStrings [ "/" ] [ "\\" ] "${p}"}";
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
      cp --no-preserve=mode ${netfx}/system32/*.dll "$WINEPREFIX/drive_c/windows/system32/" # imports are not resolved from wminet_utils.dll's own dir
      if ! grep -qF "${builtins.baseNameOf netfx}" "$WINEPREFIX/system.reg"; then
          wine reg add 'HKLM\SOFTWARE\Microsoft\.NETFramework' /v InstallRoot /t REG_SZ /d "${winPath netfx}\\" /f /reg:64
      fi
      export WINEDLLOVERRIDES="d3d8,d3d9,d3d10core,d3d11,dxgi=n,b;mshtml=" # mscoree stays builtin: CoreCLR needs it to load IL-only assemblies
      export DOTNET_ROOT="${winPath dotnet}"
    '';
    runCmd = ''wine "$WINEPREFIX/drive_c/TigerTrade/TigerTrade.exe" "$@"'';
  };
}
