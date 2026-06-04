# ZeroClaw — fast, small, autonomous AI agent runtime (https://github.com/zeroclaw-labs/zeroclaw)
# Not in nixpkgs. The crate builds from source but cargo-binstall "doesn't really work on NixOS"
# (see os/nixos/desktop/default.nix), so we pull the upstream prebuilt static-musl binary instead:
# reproducible (pinned rev+hash), no patchelf needed (statically linked), no vendoring churn.
# Bump: change `version`, then refetch and update `hash` (nix will print the correct one on mismatch).
final: prev:
let
  version = "0.7.5";
in
{
  zeroclaw = prev.stdenvNoCC.mkDerivation {
    pname = "zeroclaw";
    inherit version;

    src = prev.fetchurl {
      url = "https://github.com/zeroclaw-labs/zeroclaw/releases/download/v${version}/zeroclaw-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-AWtKqb5ayeEnat9SXLAUIrDKRPpOQ39DAc5lIGoIiM4=";
    };

    sourceRoot = ".";

    # Static-pie musl binary: nothing to patch. The tarball also ships the web dashboard
    # bundle (web/dist) that the gateway serves; keep it alongside under share/.
    installPhase = ''
      runHook preInstall
      install -Dm755 zeroclaw "$out/bin/zeroclaw"
      mkdir -p "$out/share/zeroclaw"
      cp -r web "$out/share/zeroclaw/web"
      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "Fast, small, fully autonomous AI personal assistant runtime";
      homepage = "https://github.com/zeroclaw-labs/zeroclaw";
      license = with licenses; [ mit asl20 ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "zeroclaw";
    };
  };
}
