#TODO: check this is good and expand if needed
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";

  outputs =
    { self, nixpkgs }:
    {
      devShell.default =
        let
          pkgs = import nixpkgs { };
        in
        pkgs.mkShell {
          packages = [
            (pkgs.python3.withPackages (
              python-pkgs: with python-pkgs; [
                requests # example preset
              ]
            ))
          ];
        };
    };
}
