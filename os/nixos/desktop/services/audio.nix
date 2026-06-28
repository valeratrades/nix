{ pkgs, lib, user, ... }:
let
  # Max SPL (dB) each headphone model produces at 0 dBFS, full hardware volume — a
  # measured hardware constant (manufacturer spec / Reference Audio Analyzer), not a
  # user preference. Keyed by PipeWire node.description. Used to map a user's target
  # dB-SPL ceiling to the digital threshold the limiter needs.
  calibration = {
    "WH-1000XM4" = 117;
  };
  limiters = user.sound.device_limiters or { };

  ln10 = 2.302585092994046;
  # exp(x) via Taylor series (term_n = term_{n-1}*x/n); 40 terms is far more than
  # enough for the |x| <= ~7 our dB range produces. Nix has no pow/exp natively.
  exp = x:
    (lib.foldl' (a: n: let t = a.t * x / n; in { t = t; s = a.s + t; })
      { t = 1.0; s = 1.0; } (lib.range 1 40)).s;
  dbToGain = db: exp (db / 20.0 * ln10); # linear gain of a dBFS value: 10^(dB/20)

  mkModule = desc: limitSpl:
    let
      maxSpl = calibration.${desc} or (throw
        "no headphone calibration for '${desc}' — add its max-SPL-at-0dBFS to os/nixos/desktop/services/headphone-calibration.nix");
      slug = builtins.replaceStrings [ " " ] [ "_" ] desc;
    in
    assert lib.assertMsg (limitSpl <= maxSpl)
      "sound.device_limiters: ${desc} ceiling ${toString limitSpl} dB exceeds its ${toString maxSpl} dB physical max — no limiting would apply";
    assert lib.assertMsg (limitSpl >= maxSpl - 48)
      "sound.device_limiters: ${desc} ceiling ${toString limitSpl} dB is below the limiter's -48 dBFS floor (max ${toString maxSpl} dB)";
    {
      name = "libpipewire-module-filter-chain";
      flags = [ "nofail" ];
      args = {
        "node.description" = "Headphone Safety Limiter (${desc}, ${toString limitSpl} dB SPL)";
        "audio.channels" = 2;
        "audio.position" = [ "FL" "FR" ];
        "filter.graph" = {
          nodes = [{
            type = "ladspa";
            name = "limiter";
            # found via LADSPA_PATH (extraLadspaPackages below)
            plugin = "lsp-plugins-ladspa";
            label = "http://lsp-plug.in/plugins/ladspa/limiter_stereo";
            control = {
              "Threshold (G)" = dbToGain (limitSpl - maxSpl);
              "Gain boost" = 0; # OFF: on = maximizer back to 0 dBFS, voids the cap
            };
          }];
          inputs = [ "limiter:Input L" "limiter:Input R" ];
          outputs = [ "limiter:Output L" "limiter:Output R" ];
        };
        "capture.props" = {
          "node.name" = "hp_safety_in_${slug}";
          "node.passive" = true;
        };
        "playback.props" = {
          "node.name" = "hp_safety_out_${slug}";
          "node.passive" = true;
          # Smart insertion: only ever sits in front of this device's node, so
          # speakers/builtin (and any unlisted device) stay unlimited.
          "filter.smart" = true;
          "filter.smart.name" = "hp-safety-${slug}";
          "filter.smart.targets" = [{ "node.description" = desc; }];
        };
      };
    };
in
{
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;
    # LADSPA limiter for the per-device hearing-safety smart filters below.
    extraLadspaPackages = [ pkgs.lsp-plugins ];
    # Per-device brickwall limiters generated from user.sound.device_limiters
    # (target dB SPL) and headphone-calibration.nix (max SPL at 0 dBFS).
    extraConfig.pipewire."50-headphone-safety" = lib.mkIf (limiters != { }) {
      "context.modules" = lib.mapAttrsToList mkModule limiters;
    };
  };
}
