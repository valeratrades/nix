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
    lib.lists.flatten
      [
      ];
}
