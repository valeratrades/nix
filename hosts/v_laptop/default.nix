{myvars, ...}:
#############################################################
#
# My main workspace, AMD Ryzen 7 8840U, 16Gb ddr5, 1Tb nvme ssid
#
#############################################################
let
  hostName = "v_laptop";
in {
  imports = [
    #./netdev-mount.nix
    #./hardware-configuration.nix

    #./impermanence.nix
    #./secureboot.nix
		./home.nix
		../../home/config/fish/default.nix
  ];

  #networking = {
  #  inherit hostName;
  #  inherit (myvars.networking) defaultGateway nameservers;
  #  inherit (myvars.networking.hostsInterface.${hostName}) interfaces;
  #  # desktop need its cli for status bar
  #  networkmanager.enable = true;
  #};

	# from configuration.nix:
    #firewall.allowedTCPPorts = [
    #  57621 # for spotify
    #];
    #firewall.allowedUDPPorts = [
    #  5353 # for spotify
    #];

  home.stateVersion = "24.05"; # NB: changing requires migration
}
