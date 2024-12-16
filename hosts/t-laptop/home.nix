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
  home = {
    packages =
      with pkgs;
      builtins.trace "DEBUG: sourcing Timur-specific home.nix" lib.lists.flatten [
        [
          # retarded games. Here only following Tsyren's nagging.
          prismlauncher
          modrinth-app
          jdk23
        ]
      ];
    file = {
    };
  };
}
