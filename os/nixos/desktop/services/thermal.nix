{ pkgs, ... }:
let
  # Arbitration primitive. Exactly one meaning: the scaling_max_freq this machine should sit at when
  # it is not thermally stressed. Written by whoever declares a mode (this unit at boot,
  # optimize_for on demand), read by thermal-guard so an excursion restores the *declared* baseline
  # instead of inventing one. Previously thermal-guard restored to the hardware ceiling, which would
  # have silently undone the cap after the first hot spell.
  baseFreqFile = "/run/optimize_for.base-freq";
in
{
  # Explicitly off, not merely unset: something upstream defaults it true. It is a third writer
  # racing us for platform_profile (its power-saver maps to "quiet"), and nothing here consumed its
  # D-Bus API. Ownership of platform_profile now sits solely with optimize_for + the boot default.
  services.power-profiles-daemon.enable = false;

  # Boot default: longevity. Mirrors `optimize_for longevity` so a fresh boot and an explicit
  # invocation agree.
  #
  # Boost off, but NOT capped below the base clock. schedutil already scales the cores with demand
  # (scaling_min_freq is 400 MHz), so a standing cap buys nothing while browsing and only slows the
  # work that is actually wanted — compiles get the full 2501 MHz base. Heat is handled reactively
  # by thermal-guard, on measured temperature.
  #
  # "balanced", not "performance": the only reason performance was ever set here was to buy fan
  # speed, and it charged +8 W and a 3x clock ceiling for it (boost=0, 24 threads: quiet
  # 527 MHz/33 W vs performance 1955 MHz/41 W). Airflow now has its own lever, so the profile is
  # free to sit where the power envelope should be. Not "low-power" — quiet already owns the low
  # end, and the note below rejects standing caps.
  #
  # Touches no fans. thermal-guard is their sole owner, on measured temperature.
  systemd.services.legion-longevity = {
    description = "Set Legion laptop to longevity mode (boost off, balanced power envelope)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    path = [ pkgs.bash pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      echo 0 > /sys/devices/system/cpu/cpufreq/boost
      echo balanced > /sys/firmware/acpi/platform_profile

      # Read the ceiling only after boost is settled: amd-pstate swings cpuinfo_max_freq between the
      # base and boost clocks according to it.
      ceiling=$(cat /sys/devices/system/cpu/cpufreq/policy0/cpuinfo_max_freq)
      for policy in /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq; do
        echo "$ceiling" > "$policy"
      done
      echo "$ceiling" > ${baseFreqFile}
    '';
  };

  # Battery conservation mode: cap charging to extend Li-ion cell life.
  # Li-ion cells age from time-at-high-SoC + heat; holding at 100% sits the cell
  # at ~4.2V/cell and accelerates capacity loss. Capping near 80% (~4.0V/cell)
  # slows that dramatically. Approx cycle life to 80% health vs. charge ceiling:
  #
  #   Charge ceiling | Cycles to 80% health | Relative lifespan
  #   ---------------+----------------------+------------------
  #   100%           | ~300-500             | 1x (baseline)
  #   90%            | ~600-1000            | ~2x
  #   80%            | ~1200-2000           | ~3-4x
  #
  # NB: I wanted 85%, but the Legion EC exposes only a *fixed* firmware
  # conservation cap (~80%), enforced in hardware, not a free-form percentage.
  #
  # The knob belongs to ideapad_acpi, not legion_laptop, so dropping the latter leaves it intact.
  systemd.services.legion-battery-conservation = {
    description = "Enable Legion firmware battery conservation mode (~80% charge cap)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    path = [ pkgs.bash pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      echo 1 > /sys/bus/platform/devices/VPC2004:00/conservation_mode
    '';
  };

  # Auto CPU frequency scaling (conflicts with power-profiles-daemon)
  #NB: conflicts with power-profiles-daemon, so disabled for now
  #Q: which one of the two do I actually want?
  # services.auto-cpufreq = {
  #   enable = true;
  #   settings = {
  #     charger = {
  #       governor = "performance";
  #       turbo = "auto";
  #     };
  #     battery = {
  #       governor = "powersave";
  #       turbo = "never";
  #     };
  #   };
  # };

  # The 2026-08-03 reset left nothing to argue from: the journal ends mid-line, pstore was empty,
  # and kernel.panic=0 means a panic would have hung rather than rebooted — so power was cut below
  # the kernel, and no component logs a reading on its way down. thermal-guard only speaks on a
  # threshold crossing, so the two hours before were blank. This is the missing reading.
  #
  # To journald, not a file: it is already persistent, already rotated, and on that reset it had
  # flushed to within 0.3s of the cut. `journalctl -b -1 -u sensor-sampler | tail` is the query.
  #
  # fan= is the standing check on thermal-guard's fan lever. If fanN_target silently stops being
  # honoured (across a suspend/resume, say), longevity quietly becomes balanced-with-idle-fans,
  # which is worse than what 6.12 did. Nothing else would notice.
  systemd.services.sensor-sampler = {
    description = "Sample thermals and power every 5s, so a hard reset has a last known state";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
    };
    script = ''
      hwmon_by_name() {
        for h in /sys/class/hwmon/hwmon*; do
          if [ "$(cat "$h/name" 2>/dev/null)" = "$1" ]; then echo "$h"; return; fi
        done
        echo /nonexistent
      }
      val() { cat "$1" 2>/dev/null || echo 0; }

      while true; do
        # Resolved per-sample, not cached before the loop: amdgpu and BAT0 register their hwmon in
        # the same second this unit starts, so a cached lookup raced them and logged igpu=0C ppt=0W
        # batt=0W for an entire boot — blind on exactly the two numbers a heat question needs.
        k10=$(hwmon_by_name k10temp)
        amd=$(hwmon_by_name amdgpu)
        bat=$(hwmon_by_name BAT0)
        wmi=$(hwmon_by_name lenovo_wmi_other)

        # Both DIMMs, hotter one — they read ~3C apart and either alarms at 55C.
        dram=0
        for h in /sys/class/hwmon/hwmon*; do
          if [ "$(cat "$h/name" 2>/dev/null)" = spd5118 ]; then
            t=$(( $(val "$h/temp1_input") / 1000 ))
            if [ "$t" -gt "$dram" ]; then dram=$t; fi
          fi
        done

        # Only while the dGPU is already awake. Asking otherwise wakes it out of runtime suspend
        # and, at a 5s cadence, holds it awake permanently — the sampler would become a heat source.
        # nvidia-smi is taken from the running system rather than the closure so that flipping
        # user.disableNvidia needs no change here: absent driver, absent binary, `off`.
        dgpu=off
        for d in /sys/bus/pci/drivers/nvidia/0000:*; do
          if [ "$(val "$d/power/runtime_status")" = active ] && [ -x /run/current-system/sw/bin/nvidia-smi ]; then
            dgpu=$(/run/current-system/sw/bin/nvidia-smi --query-gpu=temperature.gpu,power.draw \
              --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' | tr ',' '/')
          fi
        done

        # fmax exposes whether thermal-guard was throttling at the time; batt exposes an adapter
        # brownout, which is the leading explanation for a cut that leaves no software trace at all.
        echo "cpu=$(( $(val "$k10/temp1_input") / 1000 ))C" \
             "igpu=$(( $(val "$amd/temp1_input") / 1000 ))C" \
             "ppt=$(( $(val "$amd/power1_input") / 1000000 ))W" \
             "dgpu=$dgpu" \
             "dram=''${dram}C" \
             "fan=$(val "$wmi/fan1_input")/$(val "$wmi/fan4_input")RPM" \
             "fmax=$(( $(val /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq) / 1000 ))MHz" \
             "ac=$(val /sys/class/power_supply/ADP0/online)" \
             "batt=$(val /sys/class/power_supply/BAT0/status)/$(( $(val "$bat/power1_input") / 1000000 ))W" \
             "load=$(cut -d' ' -f1 /proc/loadavg)"

        sleep 5
      done
    '';
  };

  # The 2026-08-22 reset repeated 2026-08-03 exactly: sensor-sampler's last line, 2s before the cut,
  # read cpu=80C dram=72C dgpu=63C load=4.05 ac=1 — nothing. That rules out heat, load and a slow
  # adapter sag, and leaves machine checks as the one channel still unread. rasdaemon persists them
  # to /var/lib/rasdaemon across the reset and pulls the firmware's BERT record on the next boot,
  # which is the only place a fault below the kernel can still have left a trace.
  # `ras-mc-ctl --errors` is the query.
  hardware.rasdaemon.enable = true;

  # Two levers, one temperature. Fans ramp 65-78C, frequency is only cut at 85C —
  # the gap is the point: airflow is spent first, so a load has 20C of headroom to finish at full
  # clock before anything slows down.
  #
  # Fans are binary (firmware auto below, fanN_max above) rather than a curve, because a curve only
  # exists to trade cooling against noise and noise is not a constraint here. Idle power and the
  # fans' own heat are, which is why they are not simply pinned: below the threshold the firmware's
  # own curve runs, and it is already proportional.
  #
  # Never platform_profile. This loop used to write it, so a single thermal excursion silently
  # rewrote a profile the user had chosen; it now has exactly one owner.
  systemd.services.thermal-guard = {
    description = "Ramp fans on a per-mode curve, throttle CPU frequency at 85C";
    wantedBy = [ "multi-user.target" ];
    after = [ "legion-longevity.service" ];  # the baseline must exist before we can restore to it
    requires = [ "legion-longevity.service" ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
    };
    script = ''
      TEMP_HIGH=85000   # Start throttling at 85°C
      TEMP_LOW=75000    # Stop throttling at 75°C (hysteresis)

      # A ramp, not a switch. Three switch calibrations were tried and all failed on measurement:
      #   65/58 - release sat on the 58-59C idle floor; fans pinned permanently.
      #   72/65 - band inside the working range; flapped max<->auto 6x in 20 min.
      #   78/68 - still inside it; flapped 4x in 11 min.
      # Under a real session the CPU sweeps 67-80C continuously, so any narrow band placed in that
      # range cycles, and a wide one just means max-or-nothing. Interpolating removes the boundary
      # that was doing the flapping: a 1C drift moves the fans ~125 RPM instead of 2900.
      #
      # Handing back to the firmware below ENGAGE is not laziness, it is the quiet end done right —
      # but the firmware curve is too slack above it, measured holding 3100 of 5100 RPM while the
      # CPU drifted to 77C. RAMP_BASE sits below ENGAGE precisely so the first interpolated value
      # already exceeds what the firmware was giving there; engaging must never drop RPM.
      # Two curves, chosen by declared mode. platform_profile is already the single source of truth
      # for which mode is live, so nothing new has to be written down to tell them apart — and it is
      # re-read every iteration, so `optimize_for quiet` takes effect within 2s.
      #
      # It has to be the mode and not the power draw, because on 7.0 low-power does NOT cap this
      # machine: measured at boost=0, 24 threads, it ran 2254-2320 MHz / 42-49 W / 72-75C, i.e.
      # indistinguishable from balanced and performance. The profile is nearly inert here, so
      # "quiet" only means anything if the fan curve makes it mean something.
      #
      #   default   linear, engage 65C, fanN_max at 78C — hold TEMPERATURE down
      #   quiet     quadratic, fanN_max at 83C — hold NOISE down, accept the extra few degrees, and
      #             let the 85C frequency throttle be the backstop instead of airflow
      #
      # Quiet never hands back to the firmware curve. Handing back is what the default curve does
      # below 65C, and it is right there because the firmware is quiet at the low end — but it is
      # not quiet ENOUGH to be a quiet mode: measured 3300 RPM at 69C idle, louder than this curve's
      # own value at 75C under full load. Releasing to it would make quiet mode loudest in the exact
      # band it is supposed to cover. ENGAGE=0 is always true and RELEASE=0 never is, so the curve
      # simply owns the whole range and bottoms out at fanN_min, which is quieter than the firmware
      # ever goes and is safe by construction (it is the driver's own advertised minimum).
      curve_params() {
        if [ "$(cat /sys/firmware/acpi/platform_profile)" = low-power ]; then
          FAN_ENGAGE=0;     FAN_RELEASE=0;     RAMP_BASE=60; RAMP_TOP=83; RAMP_EXP=2
        else
          FAN_ENGAGE=65000; FAN_RELEASE=60000; RAMP_BASE=50; RAMP_TOP=78; RAMP_EXP=1
        fi
      }

      # k10temp jitters: consecutive samples bounce 68<->70 with the load unchanged. Recomputing on
      # every whole-degree step therefore mostly chases sensor noise, so hold until the reading has
      # actually moved. 2C is one deadband either side of the jitter, and at 125 RPM/°C it still
      # resolves to 250 RPM steps — well above the 100 RPM the EC quantises to.
      RAMP_DEADBAND=2

      throttled=0
      fans_engaged=0
      last_ramp=""
      last_profile=""

      # Never the hardware ceiling: the baseline is whatever mode is currently declared, so throttling
      # bites relative to the cap rather than lifting the CPU *up* to the ceiling on restore.
      # The old code restored a hardcoded 5461000 and throttled to a hardcoded 2400000 — with boost
      # off the real ceiling is 2501000, making that "throttle" a 4% cut, i.e. very nearly a no-op.
      # That is why this flapped 79<->91C every few minutes instead of ever settling.
      base() { cat ${baseFreqFile}; }

      set_freq() {
        for policy in /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq; do
          echo "$1" > "$policy" 2>/dev/null || true
        done
      }

      # Resolved per-iteration, like k10temp below: the WMI hwmon appears on the wmi bus
      # asynchronously, so it is routinely absent for the first few passes after boot. Re-reading
      # also means a write lost to a suspend/resume cycle is re-asserted within 2s rather than
      # leaving the machine silently on the firmware curve during a hot spell.
      # "$1" = auto | a temperature in millidegrees. Each channel is scaled between its own
      # fanN_min and fanN_max (they differ: 1600-5100 for fan1/fan2, 1600-6500 for fan4), and
      # rounded down to fanN_div, which the EC quantises to anyway.
      set_fans() {
        fans=$(grep -lx lenovo_wmi_other /sys/class/hwmon/*/name 2>/dev/null) || return 0
        fans=$(dirname "$fans")
        if [ "$1" = auto ]; then
          for target in "$fans"/fan*_target; do echo 0 > "$target"; done
          return 0
        fi

        # Clamped in the temperature domain, before the exponent — a negative (T - RAMP_BASE) comes
        # back positive once squared, which would ramp fans UP below the curve's own floor.
        c=$(( $1 / 1000 ))
        if [ "$c" -lt "$RAMP_BASE" ]; then c=$RAMP_BASE; fi
        if [ "$c" -gt "$RAMP_TOP" ]; then c=$RAMP_TOP; fi
        num=$(( c - RAMP_BASE ))
        den=$(( RAMP_TOP - RAMP_BASE ))
        if [ "$RAMP_EXP" -eq 2 ]; then num=$(( num * num )); den=$(( den * den )); fi

        for target in "$fans"/fan*_target; do
          lo=$(cat "''${target%_target}_min")
          hi=$(cat "''${target%_target}_max")
          div=$(cat "''${target%_target}_div")
          rpm=$(( lo + (hi - lo) * num / den ))
          echo $(( rpm / div * div )) > "$target"
        done
      }

      # Both flags above describe the *hardware*, but the hardware outlives this process: fan
      # targets and scaling_max_freq survive a restart, so a crash mid-excursion would leave the
      # machine pinned at max fans (or throttled) with a fresh loop believing it was neither, and
      # neither release branch would ever fire. Drive the state to match the assumption instead of
      # assuming it.
      curve_params
      set_fans auto
      set_freq $(base)

      while true; do
        curve_params
        # A mode switch changes every threshold at once, so the engaged state and last_ramp both
        # refer to a curve that no longer exists. Drop to auto and let the next pass re-engage
        # against the new one rather than interpolating across two different curves.
        profile=$(cat /sys/firmware/acpi/platform_profile)
        if [ "$profile" != "$last_profile" ]; then
          if [ -n "$last_profile" ] && [ "$fans_engaged" -eq 1 ]; then
            set_fans auto
            fans_engaged=0
            echo "Fans auto: profile $last_profile -> $profile, re-engaging on the new curve"
          fi
          last_profile=$profile
        fi

        # Find k10temp hwmon dynamically
        temp=""
        for hwmon in /sys/class/hwmon/hwmon*; do
          if [ "$(cat "$hwmon/name" 2>/dev/null)" = "k10temp" ]; then
            temp=$(cat "$hwmon/temp1_input" 2>/dev/null)
            break
          fi
        done

        if [ -n "$temp" ]; then
          if [ "$temp" -ge "$FAN_ENGAGE" ] && [ "$fans_engaged" -eq 0 ]; then
            fans_engaged=1
            set_fans "$temp"
            last_ramp=$(( temp / 1000 ))
            echo "Fans ramping: $((temp/1000))C, $profile curve"
          elif [ "$temp" -lt "$FAN_RELEASE" ] && [ "$fans_engaged" -eq 1 ]; then
            set_fans auto
            fans_engaged=0
            echo "Fans auto: $((temp/1000))C < $((FAN_RELEASE/1000))C"
          elif [ "$fans_engaged" -eq 1 ]; then
            # Against last_ramp, not against the previous sample: comparing neighbours lets a slow
            # drift walk any distance 1C at a time without ever tripping the deadband.
            drift=$(( temp / 1000 - last_ramp ))
            if [ "$drift" -lt 0 ]; then drift=$(( -drift )); fi
            if [ "$drift" -ge "$RAMP_DEADBAND" ]; then
              set_fans "$temp"
              last_ramp=$(( temp / 1000 ))
            fi
          fi

          if [ "$temp" -ge "$TEMP_HIGH" ] && [ "$throttled" -eq 0 ]; then
            set_freq $(( $(base) * 60 / 100 ))
            throttled=1
            echo "Throttling: $((temp/1000))C >= $((TEMP_HIGH/1000))C, freq -> $(( $(base) * 60 / 100 )) kHz"
          elif [ "$temp" -lt "$TEMP_LOW" ] && [ "$throttled" -eq 1 ]; then
            set_freq $(base)
            throttled=0
            echo "Restored: $((temp/1000))C < $((TEMP_LOW/1000))C, freq -> $(base) kHz"
          fi
        fi

        sleep 2
      done
    '';
  };
}
