# Fresh-install partitioning; WIPES the given disks. Layout picked by disk count, sizes are relative so any capacity works.
# From the installer: sudo nix run --inputs-from . disko -- --mode disko os/nixos/disko.nix --arg disks '[ "/dev/disk/by-id/<system>" "/dev/disk/by-id/<data>" ]' --argstr swap 16G
# then `nixos-generate-config --root /mnt` records the result into hardware-configuration.nix as usual (add boot.resumeDevice = the swap's by-uuid).
# Swap is last on its disk, so it can later be shrunk live into the fs before it: hosts/v-laptop/shrink-swap.sh
{ disks, swap, lib, ... }:
let
  esp = {
    priority = 1;
    size = "1G";
    type = "EF00";
    content = {
      type = "filesystem";
      format = "vfat";
      mountpoint = "/boot";
      mountOptions = [ "umask=0077" ];
    };
  };
  swapPart = {
    size = "100%";
    content.type = "swap";
  };
  ext4 = sizing: mountpoint: extraArgs: sizing // {
    content = {
      type = "filesystem";
      format = "ext4";
      inherit mountpoint extraArgs;
    };
  };
  disk = device: partitions: {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      inherit partitions;
    };
  };
in
{
  disko.devices.disk =
    if lib.length disks == 1 then {
      main = disk (lib.elemAt disks 0) {
        ESP = esp;
        root = ext4 { end = "-${swap}"; } "/" [ "-m" "1" ]; # holds /home too; 1% still leaves root GBs to recover with
        swap = swapPart;
      };
    } else if lib.length disks == 2 then {
      system = disk (lib.elemAt disks 0) {
        ESP = esp;
        root = ext4 { size = "100%"; } "/" [ ];
      };
      data = disk (lib.elemAt disks 1) {
        home = ext4 { end = "-${swap}"; } "/home" [ "-m" "1" ]; # root-reserve only matters on /, where the system writes
        swap = swapPart;
      };
    } else throw "disko.nix: no layout for ${toString (lib.length disks)} disks";
}
