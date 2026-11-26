{ pkgs, lib, user, ... }:
let
  # Max SPL (dB) each headphone model produces at 0 dBFS, full hardware volume — a
  # measured hardware constant (manufacturer spec / Reference Audio Analyzer), not a
  # user preference. Keyed by PipeWire node.description.
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

  slug = builtins.replaceStrings [ " " ] [ "_" ];
  # digital ceiling at full hardware volume; the script divides it by the gain after the limiter
  ceiling = desc: limitSpl:
    let
      maxSpl = calibration.${desc} or (throw
        "no headphone calibration for '${desc}' — add its max-SPL-at-0dBFS to the `calibration` set in os/nixos/desktop/services/audio.nix");
    in
    assert lib.assertMsg (limitSpl <= maxSpl)
      "sound.device_limiters: ${desc} ceiling ${toString limitSpl} dB exceeds its ${toString maxSpl} dB physical max — no limiting would apply";
    dbToGain (limitSpl - maxSpl);

  mkModule = desc: limitSpl:
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
              "Threshold (G)" = ceiling desc limitSpl; # until the script accounts for the volume after the limiter
              "Gain boost" = 0; # OFF: on = maximizer back to 0 dBFS, voids the cap
            };
          }];
          inputs = [ "limiter:Input L" "limiter:Input R" ];
          outputs = [ "limiter:Output L" "limiter:Output R" ];
        };
        # WirePlumber only treats the non-Stream (Audio/Sink) node as a smart filter; without it
        # both sides are plain streams and the capture one auto-links to the default mic.
        "capture.props" = {
          "node.name" = "hp_safety_in_${slug desc}";
          "media.class" = "Audio/Sink";
          # Smart insertion: only ever sits in front of this device's node, so
          # speakers/builtin (and any unlisted device) stay unlimited.
          "filter.smart" = true;
          "filter.smart.name" = "hp-safety-${slug desc}";
          "filter.smart.target" = { "node.description" = desc; };
          # Outlives its target device; must never win default-sink election (see 90-obs-virtual-mic.conf).
          "priority.session" = 0;
          "priority.driver" = 0;
        };
        "playback.props" = {
          "node.name" = "hp_safety_out_${slug desc}";
          "node.passive" = true;
        };
      };
    };

  # Smart filters never become the default sink, so the volume you set lives on the device node,
  # after the limiter. The ceiling is kept absolute by dividing it by that volume.
  script = ''
    local cutils = require ("common-utils")
    local log = Log.open_topic ("s-headphone-safety")
    local FLOOR = 0.003981 -- lsp limiter threshold minimum, -48 dB

    local devices = {
      ${lib.concatStrings (lib.mapAttrsToList (desc: limitSpl: ''
        { desc = "${desc}", slug = "${slug desc}", ceiling = ${toString (ceiling desc limitSpl)} },
      '') limiters)}
    }

    local function gain (node)
      for p in node:iterate_params ("Props") do
        local props = cutils.parseParam (p, "Props")
        if props and props.channelVolumes then
          local g = 0
          for _, v in ipairs (props.channelVolumes) do g = math.max (g, v) end
          return g * props.volume
        end
      end
      return nil -- Props not cached yet; its params-changed event comes later
    end

    local function apply (om)
      for _, d in ipairs (devices) do
        local dev = om:lookup { type = "node",
          Constraint { "media.class", "=", "Audio/Sink" }, Constraint { "node.description", "=", d.desc } }
        local filt = om:lookup { type = "node", Constraint { "node.name", "=", "hp_safety_in_" .. d.slug } }
        local out = om:lookup { type = "node", Constraint { "node.name", "=", "hp_safety_out_" .. d.slug } }
        if dev and filt and out then
          local gd, go = gain (dev), gain (out)
          if gd and go and gd * go > 0 then
            local g = gd * go
            local t = math.max (FLOOR, math.min (1.0, d.ceiling / g))
            local og = math.min (1.0, d.ceiling / (t * g)) -- past the threshold floor, attenuate after the limiter instead
            log:info (string.format ("%s: post-limiter gain %.3f -> threshold %.5f, output gain %.3f", d.desc, g, t, og))
            filt:set_params ("Props", Pod.Object { "Spa:Pod:Object:Param:Props", "Props",
              params = Pod.Struct { "limiter:Threshold (G)", Pod.Float (t), "limiter:Output gain (G)", Pod.Float (og) } })
          end
        end
      end
    end

    local function relevant (props)
      local name = props ["node.name"] or ""
      for _, d in ipairs (devices) do
        if props ["node.description"] == d.desc or name == "hp_safety_out_" .. d.slug then return true end
      end
      return false
    end

    SimpleEventHook {
      name = "headphone-safety/track-volume",
      interests = {
        EventInterest { Constraint { "event.type", "=", "node-params-changed" }, Constraint { "event.subject.param-id", "=", "Props" } },
        EventInterest { Constraint { "event.type", "=", "node-added" } },
      },
      execute = function (event)
        local props = event:get_properties ()
        -- the filter node only counts on add: our own set_params on it would re-trigger this hook
        local filter_added = props ["event.type"] == "node-added" and (props ["node.name"] or ""):find ("^hp_safety_in_")
        if not (relevant (props) or filter_added) then return end
        apply (event:get_source ():call ("get-object-manager", "node"))
      end
    }:register ()
  '';

  # The limiter's calibration is at full hardware volume, so the headset's own level is pinned there.
  # The headset keeps it, so the phone starts from it too.
  pinHwVolume = pkgs.writeShellApplication {
    name = "pin-headphone-hw-volume";
    runtimeInputs = [ pkgs.systemd pkgs.glib pkgs.gnugrep pkgs.coreutils ];
    text = ''
      pin() {
        dev=$(busctl get-property org.bluez "$1" org.bluez.MediaTransport1 Device | cut -d'"' -f2)
        alias=$(busctl get-property org.bluez "$dev" org.bluez.Device1 Alias | cut -d'"' -f2)
        case "$alias" in
          ${lib.concatMapStringsSep "|" (d: ''"${d}"'') (lib.attrNames limiters)})
            busctl set-property org.bluez "$1" org.bluez.MediaTransport1 Volume q 127
            echo "pinned $alias ($1) to 127" ;;
        esac
      }
      # a fresh transport takes writes only once AVRCP is up, which its first Volume report (the headset's stored level) marks; later reports are its own buttons
      declare -A fresh
      stdbuf -oL gdbus monitor --system --dest org.bluez | while read -r line; do
        case "$line" in
          "The name org.bluez is owned by"*) # subscribed by now, so a transport added meanwhile isn't missed
            for t in $(busctl --list tree org.bluez | grep -E '/fd[0-9]+$'); do pin "$t"; done ;;
          *InterfacesAdded*MediaTransport1*)
            t=${"$"}{line#*objectpath \'}; t=${"$"}{t%%\'*}; fresh[$t]=1 ;;
          *MediaTransport1*Volume*)
            t=${"$"}{line%%:*}
            if [[ -n ${"$"}{fresh[$t]:-} ]]; then unset "fresh[$t]"; pin "$t"; fi ;;
        esac
      done
    '';
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
    # sway runs Xwayland with `-terminate`; when it exits, x11-bell's IO-error handler segfaults pipewire (1.6.9)
    extraConfig.pipewire."10-no-x11-bell"."context.properties"."module.x11.bell" = false;
    extraConfig.pipewire."50-headphone-safety" = lib.mkIf (limiters != { }) {
      "context.modules" = lib.mapAttrsToList mkModule limiters;
    };
    wireplumber.extraScripts = lib.mkIf (limiters != { }) { "headphone-safety.lua" = script; };
    wireplumber.extraConfig."50-headphone-safety" = lib.mkIf (limiters != { }) {
      "wireplumber.components" = [{ name = "headphone-safety.lua"; type = "script/lua"; provides = "custom.headphone-safety"; }];
      "wireplumber.profiles".main."custom.headphone-safety" = "required";
      # software volume: an exact gain the script can divide by, and pipewire never overwrites the pinned hardware level
      "monitor.bluez.rules" = lib.mapAttrsToList (desc: _: {
        matches = [{ "device.description" = desc; }];
        actions.update-props."bluez5.hw-volume" = [ ];
      }) limiters;
    };
  };

  systemd.user.services.pin-headphone-hw-volume = lib.mkIf (limiters != { }) {
    wantedBy = [ "default.target" ];
    serviceConfig = { ExecStart = lib.getExe pinHwVolume; Restart = "on-failure"; };
  };
}
