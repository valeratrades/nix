{
  self,
  config,
  lib,
  pkgs,
  inputs,
  mylib,
  user,
  ...
}:
{
  home.packages =
    with pkgs;
    builtins.trace "DEBUG: sourcing Timur-specific home.nix" lib.lists.flatten [
      [
        # retarded games. Here only for Tima, TODO: remove from v right after the host config split.
        prismlauncher
        modrinth-app
        jdk23
      ]
    ];
}
