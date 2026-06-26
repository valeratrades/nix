{ config, pkgs, lib, nixos-raspberrypi, user, ... }:
#############################################################
#
# Raspberry Pi 5. Self-contained aarch64 host, built via
# `nixos-raspberrypi.lib.nixosSystem` (brings its own nixpkgs +
# vendor kernel/firmware), deliberately NOT wired through the
# x86_64/desktop machinery in outputs/default.nix.
#
#############################################################
{
  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    raspberry-pi-5.page-size-16k
    raspberry-pi-5.display-vc4
    raspberry-pi-5.bluetooth
    sd-image # provides config.system.build.sdImage
  ];

  networking.hostName = "rpi5";
  networking.networkmanager.enable = true; # ethernet DHCP works out of the box; wifi via nmcli/`hardware below`

  users.users.${user.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = user.sshAuthorizedKeys;
    initialPassword = "nixos"; # console fallback; change after first boot
  };
  users.users.root.openssh.authorizedKeys.keys = user.sshAuthorizedKeys;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };

  environment.systemPackages = with pkgs; [ vim git ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11"; # matches nixos-raspberrypi's nixpkgs; changing requires migration

  system.nixos.tags =
    let cfg = config.boot.loader.raspberry-pi;
    in [ "raspberry-pi-${cfg.variant}" cfg.bootloader config.boot.kernelPackages.kernel.version ];
}
