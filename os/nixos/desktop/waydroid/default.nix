{ pkgs
, mylib
, ...
}:
{
  environment.shellAliases.wui = "waydroid show-full-ui"; # main entry point
  # webkitgtk scare was gnome-boxes, not waydroid — closure is clean.
  virtualisation.waydroid.enable = true;

  # Container internet. waydroid-net.sh sets NAT/forwarding at session start, but the
  # firewall reload flushes its ad-hoc iptables rules and can drop the container's DHCP/DNS
  # to dnsmasq — leaving the guest with an IP but no route/resolver. Declaring it keeps it up.
  networking.firewall.trustedInterfaces = [ "waydroid0" ]; # forwarding + guest->dnsmasq (DHCP/DNS)
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  networking.firewall.extraCommands = ''
    iptables -t nat -C POSTROUTING -s 192.168.240.0/24 ! -o waydroid0 -j MASQUERADE 2>/dev/null \
      || iptables -t nat -A POSTROUTING -s 192.168.240.0/24 ! -o waydroid0 -j MASQUERADE
  ''; # uplink-agnostic masquerade (laptop roams eth/wifi)
	##NB: must run init manually as follows:
 # #- init with `sudo waydroid init -s GAPSS -f`
 # #- patch google-play certificate: https://docs.waydro.id/faq/google-play-certification
 # # normally setup also requires modyfiying waydroid_base.prop and starting up `systemctl wayland-container`, but these are taken care of below.
 # system.activationScripts.patchWaydroid = {
 #   text = ''
 #     # if the patch was already appplied, testing reversing it (\`--dry-run -R\`) returns 0
 #     if ! ${pkgs.patch}/bin/patch --dry-run -R "/var/lib/waydroid/waydroid_base.prop" < ${(mylib.relativeToRoot "os/nixos/desktop/waydroid/waydroid_base.prop.diff")} >/dev/null 2>&1; then
 #       ${pkgs.patch}/bin/patch "/var/lib/waydroid/waydroid_base.prop" < ${(mylib.relativeToRoot "os/nixos/desktop/waydroid/waydroid_base.prop.diff")}
 #     fi
 #   '';
 # };
}
