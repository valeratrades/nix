# upstream static release: nixpkgs' default pandoc lags upstream, and its newer haskellPackages builds aren't cached.
# Separate attr, so build-time consumers of `pandoc` don't rebuild.
final: prev: {
  pandoc-static = prev.stdenvNoCC.mkDerivation rec {
    pname = "pandoc-static";
    version = "3.13";
    src = prev.fetchurl {
      url = "https://github.com/jgm/pandoc/releases/download/${version}/pandoc-${version}-linux-amd64.tar.gz";
      hash = "sha256-OKozsyWivJakw5QJYxIS21VwL1ZCULzb6tGAs79kY4k=";
    };
    installPhase = "cp -r . $out";
    meta.platforms = [ "x86_64-linux" ];
  };
}
