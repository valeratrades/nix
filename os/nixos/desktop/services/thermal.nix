{ pkgs, lib, config, ... }:
{
  services.power-profiles-daemon.enable = true;

  # Lenovo Legion kernel module for fan and power control
  boot.extraModulePackages = [ config.boot.kernelPackages.lenovo-legion-module ];
  boot.extraModprobeConfig = ''
    options legion_laptop force=1
  '';

  # Default to performance profile on boot
  #TEST: if this doesn't actually heat it upu more than balanced when CPU is slow (just because of fans moving)
  systemd.services.legion-performance = {
    description = "Set Legion laptop to performance profile";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'echo performance > /sys/firmware/acpi/platform_profile'";
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
