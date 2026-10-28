# MicroSIP (SIP softphone) via Wine, inside `vpn_ns`. Portable zip: settings live in MicroSIP.ini next to the exe, so the payload is copied into the prefix.
final: prev:
let
  wineApp = prev.callPackage ./wine-wrapper.nix {};
  src = prev.fetchzip {
    url = "https://www.microsip.org/download/MicroSIP-3.22.20.zip";
    hash = "sha256-TVWcAr4CtDl51BtIryh2obYcKOQlTdjppCZGcGrGIfo=";
    stripRoot = false;
  };
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
  ''; # password appended at seed time from credentials.fish, MicroSIP encrypts it in place on first load
  wine = wineApp {
    name = "microsip-wine";
    x11 = true;
    winePrefix = "$HOME/.wine-microsip";
    runtimeInputs = [ prev.gnugrep ];
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
      if [ ! -f "$MS_DIR/MicroSIP.ini" ]; then
          pw=$(grep -Po 'set sipup_sip_pass "\K[^"]+' "$HOME/s/g/private/credentials.fish")
          cp --no-preserve=mode "${ini}" "$MS_DIR/MicroSIP.ini"
          printf 'password=%s\n' "$pw" >>"$MS_DIR/MicroSIP.ini" # [Account1] is the last section
      fi
    '';
    runCmd = ''wine "$WINEPREFIX/drive_c/MicroSIP/MicroSIP.exe" "$@"'';
  };
in {
  microsip = prev.writeShellScriptBin "microsip" ''exec ${final.vpn_ns}/bin/vpn_ns ${wine}/bin/microsip-wine "$@"'';
}
