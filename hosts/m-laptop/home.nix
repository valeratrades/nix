{ self
, config
, lib
, pkgs
, inputs
, mylib
, user
, ...
}:
{
  home.packages =
    with pkgs;
    builtins.trace "DEBUG: sourcing Masha-specific home.nix" lib.lists.flatten
      [
        arduino
      ];
}
