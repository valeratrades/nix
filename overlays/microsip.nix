# MicroSIP (SIP softphone) via Wine, inside `vpn_ns`. Portable zip: settings live in MicroSIP.ini next to the exe, so the payload is copied into the prefix.
final: prev:
let
  wineApp = prev.callPackage ./wine-wrapper.nix {};
  src = prev.fetchzip {
    url = "https://www.microsip.org/download/MicroSIP-3.22.20.zip";
    hash = "sha256-TVWcAr4CtDl51BtIryh2obYcKOQlTdjppCZGcGrGIfo=";
    stripRoot = false;
  };
  # password left out: MicroSIP encrypts whatever is typed into the account dialog into this ini
  ini = prev.writeText "MicroSIP.ini" ''
    [Settings]
    accountId=1
    [Account1]
    label=SIPUP
    server=sip.sipup.org
    proxy=
    domain=sip.sipup.org
    username=13914
    authID=13914
    password=
    displayName=
    voicemailNumber=
    dialingPrefix=
    dialPlan=
    hideCID=0
    SRTP=
    transport=tcp
    publicAddr=
    registerRefresh=300
    keepAlive=15
    publish=0
    ICE=0
    allowRewrite=0
    disableSessionTimer=0
  '';
  wine = wineApp {
    name = "microsip-wine";
    x11 = true;
    winePrefix = "$HOME/.wine-microsip";
    setupScript = ''
      export WINEDLLOVERRIDES="mscoree,mshtml=" # no .NET/IE needed, skips the Mono/Gecko install prompts
      MS_DIR="$WINEPREFIX/drive_c/MicroSIP"
      if [ ! -d "$WINEPREFIX" ]; then
          wineboot --init
      fi
      if ! cmp -s "${src}/MicroSIP.exe" "$MS_DIR/MicroSIP.exe"; then # first run or version bump; MicroSIP.ini survives
          mkdir -p "$MS_DIR"
          cp -r --no-preserve=mode "${src}"/. "$MS_DIR"
      fi
      [ -f "$MS_DIR/MicroSIP.ini" ] || cp --no-preserve=mode "${ini}" "$MS_DIR/MicroSIP.ini"
    '';
    runCmd = ''wine "$WINEPREFIX/drive_c/MicroSIP/MicroSIP.exe" "$@"'';
  };
in {
  vpn_ns = prev.writeShellApplication {
    name = "vpn_ns";
    runtimeInputs = with prev; [ passt wireguard-tools iproute2 curl util-linux coreutils ];
    text = builtins.readFile ../home/scripts/vpn_ns.sh;
  };
  microsip = prev.writeShellScriptBin "microsip" ''exec ${final.vpn_ns}/bin/vpn_ns ${wine}/bin/microsip-wine "$@"'';
}
