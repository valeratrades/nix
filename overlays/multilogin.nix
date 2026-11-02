# Multilogin X antidetect browser (official desktop .deb).
# FHS env also covers the Mimic/Stealthfox cores it downloads into ~/mlx at runtime.
final: prev:
let
  pname = "multilogin";
  version = "12.16.3";
  deb = prev.fetchurl {
    url = "https://cdn-mlx-prod.multiloginapp.com/desktop/${version}/desktop-multilogin-ubuntu-24.04-amd64.deb"; # latest version: the `desktop/latest/` links in app.multilogin.com's bundle
    hash = "sha256-SbcTYblEGcCXm9uUisnYPZj7yy174pYVAa/GM7Q6Eq0=";
  };
  contents = prev.runCommand "${pname}-${version}-contents" { nativeBuildInputs = [ prev.dpkg ]; } "dpkg-deb -x ${deb} $out";
  base = prev.appimageTools.defaultFhsEnvArgs;
in {
  multilogin = prev.buildFHSEnv (base // {
    inherit pname version;
    targetPkgs = pkgs: base.targetPkgs pkgs ++ (with pkgs; [ webkitgtk_4_1 libsoup_3 libayatana-appindicator ]);
    runScript = prev.writeShellScript "multilogin" ''
      cd ${contents}/opt/mlxapp
      exec ./desktop.bin "$@"
    '';
    extraInstallCommands = ''
      install -Dm444 ${contents}/usr/share/applications/mlxapp.desktop $out/share/applications/multilogin.desktop
      substituteInPlace $out/share/applications/multilogin.desktop \
        --replace-fail 'Exec=/opt/mlxapp/desktop.bin %u' 'Exec=multilogin %u' \
        --replace-fail 'Icon=/opt/mlxapp/mlx.png' 'Icon=multilogin' \
        --replace-fail 'Path=/opt/mlxapp/' ""
      install -Dm444 ${contents}/opt/mlxapp/mlx.png $out/share/icons/hicolor/256x256/apps/multilogin.png
    '';
  });
}
