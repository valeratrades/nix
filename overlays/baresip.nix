# baresip (terminal SIP client) inside `vpn_ns`, SIPUP account seeded on first run.
# ICE + DTLS-SRTP + rtcp-mux: the SIPUP device has WebRTC on, and sends no media to plain RTP. net_af: the namespace is v4-only.
final: prev:
let
  config = prev.writeText "baresip-config" ''
    module			stdio.so
    module			g711.so
    module			g722.so
    module			auconv.so
    module			auresamp.so
    module			pipewire.so
    module			ice.so
    module			dtls_srtp.so
    module_app		account.so
    module_app		contact.so
    module_app		menu.so
    audio_player		pipewire,default
    audio_source		pipewire,default
    audio_alert		pipewire,default
    net_af			ipv4
  '';
  launcher = prev.writeShellScript "baresip" ''
    set -euo pipefail
    dir="$HOME/.baresip"
    if [ ! -f "$dir/accounts" ]; then
        pw=$(${prev.gnugrep}/bin/grep -Po 'set sipup_sip_pass "\K[^"]+' "$HOME/s/g/private/credentials.fish")
        [[ $pw != *$'\n'* ]] || { echo "sipup_sip_pass set twice in credentials.fish" >&2; exit 1; }
        mkdir -p "$dir"
        cp --no-preserve=mode ${config} "$dir/config"
        (umask 077 && printf '<sip:13914@sip.sipup.org;transport=tcp>;auth_pass=%s;regint=300;medianat=ice;mediaenc=dtls_srtp;rtcp_mux=yes\n' "$pw" >"$dir/accounts")
    fi
    exec ${final.vpn_ns}/bin/vpn_ns ${prev.baresip}/bin/baresip "$@"
  '';
in {
  baresip = prev.symlinkJoin {
    inherit (prev.baresip) name meta;
    paths = [ prev.baresip ];
    postBuild = ''
      rm $out/bin/baresip
      ln -s ${launcher} $out/bin/baresip
    '';
  };
}
