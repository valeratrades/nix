{ self
, pkgs
, mylib
, userHome
, ...
}:
{
  imports = mylib.scanPaths ./.;
}
