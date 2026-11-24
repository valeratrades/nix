# svg goes through librsvg, as mupdf ignores gradients and clip paths; jxl mupdf does not open at all
final: prev:
let
  inherit (prev.zathuraPkgs) zathura_core zathura_djvu zathura_ps zathura_cb zathura_pdf_mupdf;

  plugin = { name, lib, pkgConfig }: prev.stdenv.mkDerivation {
    pname = "zathura-${name}";
    version = zathura_core.version;
    src = ./${name}.c;
    dontUnpack = true;
    strictDeps = true;
    nativeBuildInputs = [ prev.pkg-config ];
    buildInputs = [ zathura_core prev.girara prev.cairo lib ];
    buildPhase = ''
      $CC -std=c23 -Wall -Wextra -Werror -fPIC -shared -fvisibility=hidden -DVERSION="\"$version\"" \
        $src -o lib${name}.so $(pkg-config --cflags --libs zathura ${pkgConfig})
    '';
    installPhase = "install -Dt $out/lib/zathura lib${name}.so";
  };
in
{
  zathura = prev.zathura.override {
    plugins = [
      zathura_djvu
      zathura_ps
      zathura_cb
      (plugin { name = "svg"; lib = prev.librsvg; pkgConfig = "librsvg-2.0"; })
      (plugin { name = "jxl"; lib = prev.libjxl; pkgConfig = "libjxl libjxl_cms libjxl_threads"; })
      # zathura takes whichever plugin it happens to load first for a mime type
      (zathura_pdf_mupdf.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace zathura-pdf-mupdf/plugin.c --replace-fail '"image/svg+xml",' ""
        '';
      }))
    ];
  };
}
