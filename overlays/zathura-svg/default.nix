# zathura renders svg through librsvg: mupdf ignores gradients and clip paths
final: prev:
let
  inherit (prev.zathuraPkgs) zathura_core zathura_djvu zathura_ps zathura_cb zathura_pdf_mupdf;

  zathura_svg = prev.stdenv.mkDerivation {
    pname = "zathura-svg";
    version = zathura_core.version;
    src = ./plugin.c;
    dontUnpack = true;
    strictDeps = true;
    nativeBuildInputs = [ prev.pkg-config ];
    buildInputs = [ zathura_core prev.girara prev.cairo prev.librsvg ];
    buildPhase = ''
      $CC -std=c23 -Wall -Wextra -Werror -fPIC -shared -fvisibility=hidden -DVERSION="\"$version\"" \
        $src -o libsvg.so $(pkg-config --cflags --libs zathura librsvg-2.0)
    '';
    installPhase = "install -Dt $out/lib/zathura libsvg.so";
  };
in
{
  zathura = prev.zathura.override {
    plugins = [
      zathura_djvu
      zathura_ps
      zathura_cb
      zathura_svg
      # zathura takes whichever plugin it happens to load first for a mime type
      (zathura_pdf_mupdf.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace zathura-pdf-mupdf/plugin.c --replace-fail '"image/svg+xml",' ""
        '';
      }))
    ];
  };
}
