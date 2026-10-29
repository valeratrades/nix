# ringo (TUI over baresip) inside `vpn_ns`, SIPUP profile seeded on first run. Bare `ringo` opens that profile.
# Patched for `media_nat`/`rtcp_mux`: the SIPUP device has WebRTC on, and sends no media without ICE + rtcp-mux.
inputs: final: prev:
let
  ringo = inputs.ringo.packages.${prev.stdenv.hostPlatform.system}.ringo-phone.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./ringo-ice-rtcp-mux.patch ];
  });
  # `transport` only tags the AOR, the outbound proxy decides the actual one
  profile = prev.writeText "ringo-sipup-profile.toml" ''
    username = "13914"
    password_cmd = "grep -Po 'set sipup_sip_pass \"\\K[^\"]+' ~/s/g/private/credentials.fish"
    domain = "sip.sipup.org"
    outbound = "sip:sip.sipup.org;transport=tcp"
    media_enc = "dtls_srtp"
    media_nat = "ice"
    rtcp_mux = true
    regint = 300
    mwi = false
  ''; # mwi: SIPUP answers the subscription with 503
  config = prev.writeText "ringo.toml" ''
    [baresip.extra]
    net_af = "ipv4"
  ''; # the namespace is v4-only
  launcher = prev.writeShellScript "ringo" ''
    set -euo pipefail
    dir="$HOME/.config/ringo"
    if [ ! -f "$dir/profiles/sipup/profile.toml" ]; then
        mkdir -p "$dir/profiles/sipup"
        cp --no-preserve=mode ${profile} "$dir/profiles/sipup/profile.toml"
    fi
    [ -f "$dir/ringo.toml" ] || cp --no-preserve=mode ${config} "$dir/ringo.toml"
    [ $# -gt 0 ] || set -- start sipup
    exec ${final.vpn_ns}/bin/vpn_ns ${ringo}/bin/ringo "$@"
  '';
in {
  ringo = prev.symlinkJoin {
    inherit (ringo) name meta;
    paths = [ ringo ];
    postBuild = ''
      rm $out/bin/ringo
      ln -s ${launcher} $out/bin/ringo
    '';
  };
}
