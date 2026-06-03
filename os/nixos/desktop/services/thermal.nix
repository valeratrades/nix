{ pkgs, lib, config, ... }:
{
  services.power-profiles-daemon.enable = true;

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

  # Default to performance fan profile and CPU boost off on boot (longevity mode)
  systemd.services.legion-longevity = {
    description = "Set Legion laptop to longevity mode (boost off, fans max)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'echo 0 > /sys/devices/system/cpu/cpufreq/boost && echo performance > /sys/firmware/acpi/platform_profile'";
    };
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

  # Throttle CPU at 90°C and manage fan profile to prevent thermal shutdown
  systemd.services.thermal-guard = {
    description = "Throttle CPU and manage fans when temperature exceeds 90C";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
    };
    script = ''
      TEMP_HIGH=90000   # Start throttling at 90°C
      TEMP_LOW=80000    # Stop throttling at 80°C (hysteresis)
      FREQ_THROTTLE=2400000  # ~44% of max
      FREQ_NORMAL=5461000
      PLATFORM_PROFILE="/sys/firmware/acpi/platform_profile"

      throttled=0

      set_freq() {
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
          echo "$1" > "$cpu" 2>/dev/null || true
        done
      }

      set_fan_profile() {
        echo "$1" > "$PLATFORM_PROFILE" 2>/dev/null || true
      }

      get_fan_profile() {
        cat "$PLATFORM_PROFILE" 2>/dev/null || echo "unknown"
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

        # Never allow quiet profile - power-profiles-daemon sets this with power-saver
        current_profile=$(get_fan_profile)
        if [ "$current_profile" = "quiet" ]; then
          set_fan_profile "balanced"
          echo "Fan profile: quiet -> balanced (quiet not allowed)"
        fi

        if [ -n "$temp" ]; then
          if [ "$temp" -ge "$TEMP_HIGH" ] && [ "$throttled" -eq 0 ]; then
            set_freq $FREQ_THROTTLE
            set_fan_profile "performance"
            throttled=1
            echo "Throttling: $((temp/1000))C >= 90C, fans -> performance"
          elif [ "$temp" -lt "$TEMP_LOW" ] && [ "$throttled" -eq 1 ]; then
            set_freq $FREQ_NORMAL
            set_fan_profile "balanced"
            throttled=0
            echo "Restored: $((temp/1000))C < 80C, fans -> balanced"
          fi
        fi

        sleep 2
      done
    '';
  };
}
