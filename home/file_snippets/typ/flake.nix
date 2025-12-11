{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    v-utils.url = "github:valeratrades/.github";
  };

  outputs = { self, nixpkgs, flake-utils, v-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        pname = "PROJECT_NAME_PLACEHOLDER";

        readme = v-utils.readme-fw {
          inherit pkgs pname;
          lastSupportedVersion = "";
          rootDir = ./.;
          licenses = [{ name = "Blue Oak 1.0.0"; outPath = "LICENSE"; }];
          badges = [ "loc" ];
        };
      in
      {
        packages.default = pkgs.stdenvNoCC.mkDerivation {
          name = "${pname}-document";
          src = ./.;

          nativeBuildInputs = [ pkgs.typst ];

          buildPhase = ''
            typst compile __main__.typ output.pdf
          '';

          installPhase = ''
            mkdir -p $out
            cp output.pdf $out/
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.typst ];

          shellHook = ''
            cp -f ${v-utils.files.licenses.blue_oak} ./LICENSE
            cp -f ${
              (v-utils.files.gitignore {
                inherit pkgs;
                langs = [ ];
              })
            } ./.gitignore
            cp -f ${ (v-utils.files.gitLfs { inherit pkgs; }) } ./.gitattributes
            cp -f ${readme} ./README.md
          '';
        };
      }
    );
}
