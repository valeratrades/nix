{ myvars, mylib, ... }:
#############################################################
#
# My main workspace, AMD Ryzen 7 8840U, 16Gb ddr5, 1Tb nvme ssid
#
#############################################################
let
  hostName = "v-laptop";
in
{
  imports = [
    #./netdev-mount.nix
    #./hardware-configuration.nix

    #./impermanence.nix
    #./secureboot.nix
    ./home.nix
    #mylib.relativeToRoot "./home/config/fish/default.nix"
    ../../home/config/fish/default.nix
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
