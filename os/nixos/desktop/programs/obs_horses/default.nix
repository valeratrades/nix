# Self-contained OBS addon owning the Camera scene's background: cut out in composited scenes, kept in the camera-only one.
# While `$XDG_RUNTIME_DIR/obs_horses` exists (sway obs-mode `h` on, `H` off) and a key was just pressed, a gallop plays behind the camera:
# through the cutout in composited scenes, around the camera frame in the camera-only one.
# State shows in OBS's status bar. Nothing of it is ever saved into the scene collection.
{ pkgs, lib, user, ... }:
let
  stopAfterMs = 130; # horses keep running this long after the last key is released

  # Muybridge's 1878 gallop (public domain, commons.wikimedia.org/wiki/File:Muybridge_race_horse_animated.gif) as a 4x3 herd, each horse phase-shifted
  tiles = lib.genList (i: rec { inherit i; col = lib.mod i 4; row = i / 4; phase = lib.mod (7 * row + 4 * col) 15; }) 12;
  herd = pkgs.runCommand "horses.gif" { nativeBuildInputs = [ pkgs.ffmpeg ]; } ''
    ffmpeg -v error ${lib.concatMapStrings (_: "-ignore_loop 0 -i ${./muybridge.gif} ") tiles} -filter_complex "${
      lib.concatMapStrings (t: "[${toString t.i}:v]trim=start_frame=${toString t.phase}:end_frame=${toString (t.phase + 15)},setpts=PTS-STARTPTS[t${toString t.i}];") tiles
    }${lib.concatMapStrings (t: "[t${toString t.i}]") tiles}xstack=inputs=12:layout=${
      lib.concatMapStringsSep "|" (t: "${toString (300 * t.col)}_${toString (200 * t.row)}") tiles
    },split[a][b];[a]palettegen[p];[b][p]paletteuse" -loop 0 -f gif $out
  '';

  plugin = pkgs.stdenv.mkDerivation {
    name = "obs-horses";
    src = ./horses.cpp;
    dontUnpack = true;
    dontWrapQtApps = true; # a plugin, OBS's own wrapper provides the Qt env
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.obs-studio pkgs.qt6.qtbase ]; # same qtbase OBS links, two Qts in one process would crash
    buildPhase = "$CXX -std=c++20 -shared -fPIC -Wall -Wextra -Werror $src -I${pkgs.obs-studio}/include/obs -L${pkgs.obs-studio}/lib -lobs -lobs-frontend-api $(pkg-config --cflags --libs Qt6Widgets) -o horses.so";
    installPhase = ''
      install -Dm755 horses.so $out/bin/64bit/horses.so
      install -Dm644 ${herd} $out/data/horses.gif
    '';
  };
in
{
  # per-user plugin dir: OBS loads it next to the wrapOBS ones
  home-manager.users.${user.username}.home.file.".config/obs-studio/plugins/horses".source = plugin;

  # evdev needs the `input` group; this keeps that away from the session, exposing only a typing bit
  users.users.obs-typing = { isSystemUser = true; group = "obs-typing"; };
  users.groups.obs-typing = { };
  systemd.services.obs-typing = {
    description = "Typing indicator for the OBS horses plugin";
    wantedBy = [ "multi-user.target" ];
    after = [ "keyd.service" ];
    startLimitIntervalSec = 0; # keyd recreates its virtual keyboard on restart; retry until it's back
    serviceConfig = {
      ExecStart = "${pkgs.python3.withPackages (ps: [ ps.evdev ])}/bin/python3 -I ${./typing_bit.py} /run/obs-typing/typing ${toString stopAfterMs}";
      User = "obs-typing"; # static: DynamicUser hides preserved runtime dirs under root-only /run/private
      SupplementaryGroups = [ "input" ];
      RuntimeDirectory = "obs-typing";
      # a stopped detector means nobody is typing; without these a `switch` restart makes the plugin see a missing file and toggle itself off
      RuntimeDirectoryPreserve = true;
      ExecStopPost = "${pkgs.runtimeShell} -c 'printf 0 > /run/obs-typing/typing'";
      Restart = "always";
      RestartSec = 1;
    };
  };
}
