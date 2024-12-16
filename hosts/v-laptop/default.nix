{ user, mylib, ... }:
#############################################################
#
# My main workspace, AMD Ryzen 7 8840U, 16Gb ddr5, 1Tb nvme ssid
#
#############################################################
let
  hostName = user.desktopHostName; # could be different for servers, which would prompt the need for manual setting of it right here.
in
{
  imports = [
    #./netdev-mount.nix
    #./hardware-configuration.nix

    #./impermanence.nix
    #./secureboot.nix

    ../shared/home.nix # NB: must be above home.nix
    ./home.nix
  ];

  #networking = {
  #inherit hostName;
  #TODO!: \
  #  inherit (myvars.networking) defaultGateway nameservers;
  #  inherit (myvars.networking.hostsInterface.${hostName}) interfaces;
  # desktop need its cli for status bar
  #networkmanager.enable = true;
  #};

  home.stateVersion = "24.05"; # NB: changing requires migration
}
