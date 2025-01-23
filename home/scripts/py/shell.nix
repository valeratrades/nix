{
  pkgs ? import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/master.tar.gz") { },
}:

pkgs.mkShellNoCC {
  packages = with pkgs; [
    (python3.withPackages (ps: [
      ps.numpy
      ps.transformers
      ps.torch
      ps.soundfile
      ps.datasets
    ]))
  ];
}
