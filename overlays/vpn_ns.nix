# `vpn_ns <cmd>`: run a program with all its traffic through Proton VPN, see home/scripts/vpn_ns.sh
final: prev: {
  vpn_ns = prev.writeShellApplication {
    name = "vpn_ns";
    runtimeInputs = with prev; [ passt wireguard-tools iproute2 curl util-linux coreutils systemd ];
    text = builtins.readFile ../home/scripts/vpn_ns.sh;
  };
}
