# baresip (terminal SIP client) inside `vpn_ns`, SIPUP account seeded on first run.
final: prev:
let
  config = prev.writeText "baresip-config" ''
    module			stdio.so
    module			g711.so
    module			g722.so
    module			auconv.so
    module			auresamp.so
    module			pipewire.so
    module_app		account.so
    module_app		contact.so
    module_app		menu.so
    audio_player		pipewire,default
    audio_source		pipewire,default
    audio_alert		pipewire,default
  '';
  launcher = prev.writeShellScript "baresip" ''
    set -euo pipefail
    dir="$HOME/.baresip"
    if [ ! -f "$dir/accounts" ]; then
        pw=$(${prev.gnugrep}/bin/grep -Po 'set sipup_sip_pass "\K[^"]+' "$HOME/s/g/private/credentials.fish")
        mkdir -p "$dir"
        cp --no-preserve=mode ${config} "$dir/config"
        (umask 077 && printf '<sip:13914@sip.sipup.org;transport=tcp>;auth_pass=%s;regint=300\n' "$pw" >"$dir/accounts")
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
