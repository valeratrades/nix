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
        pre-commit-check = pre-commit-hooks.lib.${system}.run (v_flakes.files.preCommit {
          inherit pkgs;
          webAssets = { };
        });

        github = v_flakes.github {
          inherit pkgs pname;
          enable = true;
        };
        readme = v_flakes.readme-fw {
          inherit pkgs pname;
          defaults = true;
          lastSupportedVersion = "";
          rootDir = ./.;
          badges = [ "loc" ];
        };
        combined = v_flakes.utils.combine { rust = v_flakes.rs.default_nightly system; modules = [ github readme ]; };
      in
      {
        apps.help = v_flakes.utils.help { inherit pkgs self system; };

        packages.default = pkgs.runCommand pname { } ''
          cp -r ${pkgs.lib.cleanSource ./.} $out
        '';

        devShells.default = pkgs.mkShell {
          shellHook =
            pre-commit-check.shellHook
            + combined.shellHook
            + ''
              cp -f ${(v_flakes.files.treefmt) { inherit pkgs; }} ./.treefmt.toml
            '';

          packages = pre-commit-check.enabledPackages ++ combined.enabledPackages;
        };
      }
    );
}
