# GoLogin antidetect browser (official Linux AppImage).
# FHS env via wrapType2 also covers the Orbita browser it downloads into ~/.gologin at runtime.
final: prev:
let
  pname = "gologin";
  version = "4.14.1";
  src = prev.fetchurl {
    url = "https://releases.gologin.com/Gologin-${version}"; # version + sha512 from https://releases.gologin.com/latest-linux.yml
    hash = "sha512-TLjEea+7G/tw7LRZBQMqv7qp7MCWAvqHfoKq8HUBGmXZm3QawOoHhDT25dMt6gUiEkkJjuRblpNBJHfVTsfrpQ==";
  };
  contents = prev.appimageTools.extract { inherit pname version src; };

  # Orbita is built against Debian's libcurl3-gnutls: needs soname libcurl-gnutls.so.4 exporting CURL_GNUTLS_3
  curlDebianGnutls =
    let
      curl = prev.curlWithGnuTls.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace lib/libcurl.vers.in --replace-fail '@CURL_LIBCURL_VERSIONED_SYMBOLS_SONAME@' 3
        '';
      });
    in
    prev.runCommand "libcurl-gnutls-debian" { nativeBuildInputs = [ prev.patchelf ]; } ''
      install -Dm755 ${prev.lib.getLib curl}/lib/libcurl.so.4 $out/lib/libcurl-gnutls.so.4
      patchelf --set-soname libcurl-gnutls.so.4 $out/lib/libcurl-gnutls.so.4
    '';
in {
  gologin = prev.appimageTools.wrapType2 {
    inherit pname version src;
    extraPkgs = _: [ curlDebianGnutls ];
    extraInstallCommands = ''
      install -Dm444 ${contents}/gologin.desktop $out/share/applications/gologin.desktop
      substituteInPlace $out/share/applications/gologin.desktop --replace-fail 'Exec=AppRun' 'Exec=gologin'
      echo 'MimeType=x-scheme-handler/gologin;' >> $out/share/applications/gologin.desktop # login redirects back via gologin://
      install -Dm444 ${contents}/gologin.png $out/share/icons/hicolor/512x512/apps/gologin.png
    '';
  };
}
