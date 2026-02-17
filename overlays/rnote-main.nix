# Overlay to pin rnote to v0.13.1 (2025-09-09)
final: prev:
let
  version = "0.13.1";
  src = prev.fetchFromGitHub {
    owner = "flxzt";
    repo = "rnote";
    rev = "v0.13.1";
    hash = "sha256-EMxA5QqmIae/d3nUpwKjgURo0nOyaNbma8poB5mcQW0=";
  };
in {
  rnote = prev.rnote.overrideAttrs (old: {
    inherit version src;

    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit (old) pname;
      inherit version src;
      hash = "sha256-fr1bDTzTKx7TLBqw94CyaB0/Jo2x1BzZcM6dcen1PHc=";
    };
  });
}
