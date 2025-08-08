{ mylib, ... }:
{
  imports = builtins.trace "DEBUG: loading programs" mylib.scanPaths ./.;
}
