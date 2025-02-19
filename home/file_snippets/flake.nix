{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";

  outputs =
    { self, nixpkgs }:
    {
      devShell.default =
        let
          pkgs = import nixpkgs {
            allowUnfree = true;
          };
        in
        pkgs.mkShell {
          packages = with pkgs; [
            cargo
            fd
            ripgrep
            go
            elan
            git
            python3Full
          ];
        };
    };
}
