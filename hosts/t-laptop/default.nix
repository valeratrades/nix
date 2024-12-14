{ user, mylib, ... }:
#############################################################
#
# Timur's main workspace, 512GB NVMe, 16GB ddr5, AMD Ryzen 5 7640HS
#
#############################################################
{
  imports = [
    ../shared
    ./home.nix
  ];
  home.stateVersion = "24.05"; # NB: changing requires migration
}
