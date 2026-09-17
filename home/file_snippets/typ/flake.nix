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
        # Only the label sync — the rest of the module writes rust CI workflows
        # and wants a toolchain this repo has no use for.
        github = v_flakes.github { inherit pkgs pname; enable = true; };
        readme = v_flakes.readme-fw {
          inherit pkgs pname;
          defaults = true;
          lastSupportedVersion = "";
          rootDir = ./.;
          badges = [ "loc" ];
        };
        readmeHook = v_flakes.utils.unwrapShellHook readme.shellHook;
        typstyleFmt = pkgs.writeShellScriptBin "typstyle-fmt" ''
          exec ${pkgs.typstyle}/bin/typstyle --line-width 190 --indent-width 2 "$@"
        '';
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
            + readmeHook
            + ''
              cp -f ${(v_flakes.files.treefmt) { inherit pkgs; }} ./.treefmt.toml
              cp -f ${(v_flakes.files.gitignore { inherit pkgs; langs = [ ]; extra = "*.pdf"; })} ./.gitignore
            ''
            + github.labelSyncHook;

          packages = [ pkgs.treefmt typstyleFmt ]
            ++ pre-commit-check.enabledPackages
            ++ typ.enabledPackages
            ++ readme.enabledPackages;
        };
      }
    );
}
