{ mylib, ... }:
{
  imports = mylib.scanPaths ./. ++ [
    (mylib.relativeToRoot "home/config/fish/default.nix")
  ];
}
