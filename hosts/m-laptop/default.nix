{ user, mylib, ... }:
#############################################################
#
# Masha's main workspace, some intel laptop 256GB NVMe, 8GB ddr4(?or 5?)
#
#############################################################
{
  imports = [
    ../shared/home.nix
    ./home.nix
  ];
  home.stateVersion = "24.05"; # NB: changing requires migration
}
