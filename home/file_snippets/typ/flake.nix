{
  nixConfig = {
    extra-substituters = [ "https://valeratrades.cachix.org" ];
    extra-trusted-public-keys = [ "valeratrades.cachix.org-1:gXVwhzO5YB+BaiEJYT48qZgzdaErGQew6xtZcz4Fo1Q=" ];
  };

  inputs = {
    v_flakes.url = "github:valeratrades/v_flakes?ref=v1.6";
  };

  outputs = { self, v_flakes }:
    let
      inherit (v_flakes) flake-utils pre-commit-hooks;
      pname = "PROJECT_NAME_PLACEHOLDER";
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import v_flakes.default_nixpkgs { inherit system; };
        pre-commit-check = pre-commit-hooks.lib.${system}.run (v_flakes.files.preCommit { inherit pkgs; });

        typ = v_flakes.typ { inherit pkgs; lsp = true; };
        typst = pkgs.typst.withPackages (p: with p; [ charged-ieee ]); # nix build has no network for `@preview` imports
        github = v_flakes.github {
          inherit pkgs pname;
          enable = true;
          gitignore.extra = "*.pdf";
        };
        readme = v_flakes.readme-fw {
          inherit pkgs pname;
          defaults = true;
          lastSupportedVersion = "";
          rootDir = ./.;
          badges = [ "loc" ];
        };
        combined = v_flakes.utils.combine { rust = v_flakes.rs.default_nightly system; modules = [ readme typ github ]; };
      in
      {
        apps.help = v_flakes.utils.help {
          inherit pkgs self system;
          about = "typst watch __main__.typ output.pdf   live rebuild";
        };

        apps.default = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "build" ''
            exec ${typst}/bin/typst compile __main__.typ output.pdf
          ''}/bin/build";
          meta.description = "compile __main__.typ into output.pdf";
        };

        packages.default = pkgs.stdenvNoCC.mkDerivation {
          name = "${pname}-document";
          src = ./.;
          meta.description = "__main__.typ compiled to output.pdf";

          nativeBuildInputs = [ typst ];

          buildPhase = ''
            typst compile __main__.typ output.pdf
          '';

          installPhase = ''
            mkdir -p $out
            cp output.pdf $out/
          '';
        };

        devShells.default = pkgs.mkShell {
          shellHook =
            pre-commit-check.shellHook
            + combined.shellHook
            + ''
              cp -f ${(v_flakes.files.treefmt) { inherit pkgs; }} ./.treefmt.toml
            '';

          packages = [ typst ] ++ pre-commit-check.enabledPackages ++ combined.enabledPackages;
        };
      }
    );
}
