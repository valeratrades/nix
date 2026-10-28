# Linphone (native SIP softphone) inside `vpn_ns`, SIPUP account seeded on first run.
final: prev:
let
  patched = prev.linphone.overrideAttrs (o: {
    # each start rewrites ~/.local/share/applications/linphone.desktop with Exec= the unwrapped binary, which would skip vpn_ns
    postPatch = (o.postPatch or "") + ''
      substituteInPlace Linphone/core/App.cpp --replace-fail "exportDesktopFile();" ""
    '';
  });
  rc = prev.writeText "linphonerc" ''
    [proxy_0]
    reg_proxy=<sip:sip.sipup.org;transport=tcp>
    reg_identity=sip:13914@sip.sipup.org
    reg_expires=300
    reg_sendregister=1
    publish=0

    [auth_info_0]
    username=13914
    userid=13914
    domain=sip.sipup.org
  ''; # passwd appended at seed time from credentials.fish
  launcher = prev.writeShellScript "linphone" ''
    set -euo pipefail
    conf="''${XDG_CONFIG_HOME:-$HOME/.config}/linphone"
    if [ ! -f "$conf/linphonerc" ]; then
        mkdir -p "$conf"
        pw=$(${prev.gnugrep}/bin/grep -Po 'set sipup_sip_pass "\K[^"]+' "$HOME/s/g/private/credentials.fish")
        cp --no-preserve=mode ${rc} "$conf/linphonerc"
        printf 'passwd=%s\n' "$pw" >>"$conf/linphonerc" # [auth_info_0] is the last section
    fi
    exec ${final.vpn_ns}/bin/vpn_ns ${patched}/bin/linphone "$@"
  '';
in {
  linphone = prev.symlinkJoin {
    inherit (patched) name meta;
    paths = [ patched ];
    postBuild = ''
      rm $out/bin/linphone
      ln -s ${launcher} $out/bin/linphone
    '';
  };
}
