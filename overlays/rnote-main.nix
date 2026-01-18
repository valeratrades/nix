# Overlay to use rnote from latest main branch
final: prev:
let
  version = "0-unstable-2025-01-17";
  src = prev.fetchFromGitHub {
    owner = "flxzt";
    repo = "rnote";
    rev = "ddc89dac5264919d71772c1c8d935468c9e14132";
    hash = "sha256-+x+5M7qqhqjP3a1GHbanFallIACz2IzVAvX8WDxS3wo=";
  };
in {
  rnote = prev.rnote.overrideAttrs (old: {
    inherit version src;

    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit (old) pname;
      inherit version src;
      hash = "sha256-yNK2WNcv70h6qWfUgAEp8fGEBqM2PQWNknWoyRcsrXE=";
    };
  });
}
