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
        hooks = builtins.concatStringsSep "" (
          map v_flakes.utils.unwrapShellHook [ readme.shellHook typ.shellHook github.shellHook ]
        );
      in
      {
        apps.help = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "help" ''
            cat <<EOF
            nix build .#default   Build __main__.typ into output.pdf
            nix develop           Enter the Typst development shell
            typst watch __main__.typ output.pdf   Watch and rebuild the document
            EOF
          ''}/bin/help";
        };

        apps.default = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "build" ''
            exec typst compile __main__.typ output.pdf
          ''}/bin/build";
        };

        packages.help = pkgs.writeShellScriptBin "help" ''
          cat <<EOF
          nix build .#default   Build __main__.typ into output.pdf
          nix develop           Enter the Typst development shell
          typst watch __main__.typ output.pdf   Watch and rebuild the document
          EOF
        '';

        packages.build = pkgs.writeShellScriptBin "build" ''
          exec typst compile __main__.typ output.pdf
        '';

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
          shellHook =
            pre-commit-check.shellHook
            + hooks
            + ''
              cp -f ${(v_flakes.files.treefmt) { inherit pkgs; }} ./.treefmt.toml
            '';

          packages = pre-commit-check.enabledPackages
            ++ typ.enabledPackages
            ++ readme.enabledPackages
            ++ github.enabledPackages;
        };
      }
    );
}
