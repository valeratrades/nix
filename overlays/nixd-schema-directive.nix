# nixd from valeratrades/nixd@schema-directive, which teaches it to read a
# `#:schema <module>` line off a config's first line and use that module's
# options for that file alone. Upstream resolves option sets only through
# editor settings, so a generated config cannot describe itself.
# Drop this overlay if it lands upstream; RFC at nix-community/nixd#889.
final: prev:
{
  nixd = prev.callPackage (prev.fetchFromGitHub {
    owner = "valeratrades";
    repo = "nixd";
    rev = "dce5f1e9e2666f4c71ca919166c1e07dab7daca1";
    hash = "sha256-ZojyEL45VuuKBPOJ9TpxMNagiqTe9qu9GmbGNNulgzM=";
  }) {
    # Matching the versions nixd's own flake builds against; nixpkgs' 2.9.x
    # derivation predates both.
    nixComponents = prev.nixVersions.nixComponents_2_34;
    llvmPackages = prev.llvmPackages_21;
  };
}
