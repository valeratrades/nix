{
  inputs,
  config,
  lib,
  ...
}:
{
  security.sudo.execWheelOnly = lib.mkForce false;

  imports = [
    ./fhs-compat.nix
  ];
}

