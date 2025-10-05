{ config, pkgs, lib, user, mylib, inputs, ... }:

{
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal-combined.nix>
    ./server.nix
    ./shared
    (mylib.relativeToRoot "./hosts/${user.desktopHostName}/configuration.nix")
    (if builtins.pathExists "/etc/nixos/hardware-configuration.nix" then
      /etc/nixos/hardware-configuration.nix
    else
      builtins.trace
      "WARNING: Falling back to ./hosts/${user.desktopHostName}/hardware-configuration.nix, as /etc/nixos/hardware-configuration.nix does not exist. Could cause problems."
      mylib.relativeToRoot
      "./hosts/${user.desktopHostName}/hardware-configuration.nix")
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "24.05";
}