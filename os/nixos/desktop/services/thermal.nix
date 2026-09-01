{ pkgs, lib, config, ... }:
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

  # Allow users in 'wheel' group to control CPU boost and platform profile
  services.udev.extraRules = ''
    KERNEL=="boost", SUBSYSTEM=="cpufreq", MODE="0664", GROUP="wheel"
    KERNEL=="platform_profile", SUBSYSTEM=="acpi", MODE="0664", GROUP="wheel"
  '';

  # Lenovo Legion kernel module for fan and power control
  boot.extraModulePackages = [ config.boot.kernelPackages.lenovo-legion-module ];
  boot.extraModprobeConfig = ''
    options legion_laptop force=1
  '';

  # Boot default: longevity. Mirrors `optimize_for longevity` so a fresh boot and an explicit
  # invocation agree.
  #
  # Boost off, but NOT capped below the base clock. schedutil already scales the cores with demand
  # (scaling_min_freq is 400 MHz), so a standing cap buys nothing while browsing and only slows the
  # work that is actually wanted — compiles get the full 2501 MHz base. Heat is handled reactively
  # by thermal-guard, on measured temperature.
  #
  # BUG!!!!!!!: platform_profile stays "performance" purely for the fan curve, and the same knob
  # raises the power envelope. Measured at boost=0, 24 threads: quiet 600 MHz/33 W vs performance
  # 1955 MHz/41 W. `longevity` therefore asks for airflow and gets +8 W with it.
  # No independent fan lever survives because legion_laptop is force-loaded with the GKCN register
  # map on this RLCN EC, so every EC-mediated knob is inert.
  # See ongoing_debug/2026-07-26_cpu-thermals.md §"2026-09-01: reopened".
  systemd.services.legion-longevity = {
    description = "Set Legion laptop to longevity mode (boost off, fans max)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    path = [ pkgs.bash pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      echo 0 > /sys/devices/system/cpu/cpufreq/boost
      echo performance > /sys/firmware/acpi/platform_profile

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
  # The legion_cli `custom-conservation-mode-apply LOWER UPPER` band exists but
  # only emulates a custom limit via a continuous software poll-and-toggle loop,
  # i.e. a breakable soft cap. We take the firmware-enforced ~80% instead; the
  # 80-vs-85 longevity difference is within the noise of the table above.
  systemd.services.legion-battery-conservation = {
    description = "Enable Legion firmware battery conservation mode (~80% charge cap)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    # legion_cli shells out to `bash` internally, so it needs it on PATH;
    # systemd units run with an empty PATH by default.
    path = [ pkgs.bash pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.lenovo-legion}/bin/legion_cli batteryconservation-enable";
    };
  };

  # Userspace utility for Legion fan control
  environment.systemPackages = [ pkgs.lenovo-legion ];

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
  # legion_hwmon is deliberately absent. Its registers latch: it reported a fixed 87C GPU across
  # every sample while nvidia-smi read 57C, and fan speeds above its own advertised maximum. That
  # is the same brokenness eww's temperature.sh already routes around.
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

  # Throttle CPU frequency at 90°C to prevent thermal shutdown.
  #
  # Deliberately touches frequency ONLY, and only relative to the declared baseline. This loop used
  # to be a second writer of platform_profile, so a single thermal excursion silently rewrote a
  # profile the user had chosen; the profile now has exactly one owner.
  systemd.services.thermal-guard = {
    description = "Throttle CPU frequency when temperature exceeds 90C";
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

      throttled=0

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

      while true; do
        # Find k10temp hwmon dynamically
        temp=""
        for hwmon in /sys/class/hwmon/hwmon*; do
          if [ "$(cat "$hwmon/name" 2>/dev/null)" = "k10temp" ]; then
            temp=$(cat "$hwmon/temp1_input" 2>/dev/null)
            break
          fi
        done

        if [ -n "$temp" ]; then
          if [ "$temp" -ge "$TEMP_HIGH" ] && [ "$throttled" -eq 0 ]; then
            set_freq $(( $(base) * 60 / 100 ))
            throttled=1
            echo "Throttling: $((temp/1000))C >= 90C, freq -> $(( $(base) * 60 / 100 )) kHz"
          elif [ "$temp" -lt "$TEMP_LOW" ] && [ "$throttled" -eq 1 ]; then
            set_freq $(base)
            throttled=0
            echo "Restored: $((temp/1000))C < 80C, freq -> $(base) kHz"
          fi
        fi

        sleep 2
      done
    '';
  };
}
