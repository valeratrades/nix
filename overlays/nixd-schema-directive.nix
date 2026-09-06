# nixd from valeratrades/nixd@schema-directive, which teaches it to read a
# `#:schema <module>` line off a config's first line and use that module's
# options for that file alone -- for completion, hover and definition, and to
# typecheck the file against them. Upstream resolves option sets only through
# editor settings, so a generated config cannot describe itself, and nothing
# tells nixd which files are modules at all.
# Drop this overlay if it lands upstream; RFC at nix-community/nixd#889.
final: prev:
{
  nixd = prev.callPackage (prev.fetchFromGitHub {
    owner = "valeratrades";
    repo = "nixd";
    rev = "7fcdc56452ccfe2c37ca66b1b70fd440f6a473e5";
    hash = "sha256-cyvikKVDVvuwAjxDyXNEZF7vmbakHfET5at0fbwyEds=";
  }) {
    # Matching the versions nixd's own flake builds against; nixpkgs' 2.9.x
    # derivation predates both.
    nixComponents = prev.nixVersions.nixComponents_2_34;
    llvmPackages = prev.llvmPackages_21;
  };
}
