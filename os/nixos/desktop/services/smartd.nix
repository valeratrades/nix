{ pkgs, ... }:
{
  services.smartd = {
    enable = true;
    # Check every 30 minutes; alert on any new error, temperature warning, or attribute change
    autodetect = true;
    defaults.monitored = "-a -o on -s (S/../.././02|L/../01/./02) -W 5,55,65 -m root";
    notifications = {
      wall.enable = true;
      x11.enable = false;
      test = false;
      systembus-notify.enable = true;
    };
  };

  # smartd only alerts once spare runs out; a write-rate alarm catches a misconfigured fs/build burning the drive while it's still healthy
  systemd.services.nvme-health-log = {
    description = "Log NVMe health snapshot, alert on runaway write rate";
    path = [ pkgs.smartmontools pkgs.gnugrep pkgs.jq pkgs.dbus ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "nvme-health";
      ExecStart = pkgs.writeShellScript "nvme-health-log" ''
        set -eu
        max_gb_per_h=30 # lifetime avg on nvme0 is ~20GB per power-on hour
        log=/var/log/nvme-health.log
        now=$(date +%s)
        for dev in nvme0n1 nvme1n1; do
          smartctl -A /dev/$dev | grep -E '(Media|Error|Unsafe|Warning|Critical|Available Spare|Percentage Used|Data Units Written)' >> $log
          echo "---" >> $log
          written=$(smartctl -j -A /dev/$dev | jq -e .nvme_smart_health_information_log.data_units_written) # units of 512000B
          state=$STATE_DIRECTORY/$dev
          if [ -f $state ]; then
            read -r prev_t prev_w < $state
            gb=$(( (written - prev_w) * 512 / 1000000 ))
            h=$(( (now - prev_t) / 3600 + 1 ))
            if [ $(( gb / h )) -gt $max_gb_per_h ]; then
              msg="$dev: $gb GB written in under $h h (over $max_gb_per_h GB/h)"
              echo "ALERT $msg" >> $log
              dbus-send --system / net.nuetzlich.SystemNotifications.Notify "string:SSD write rate" "string:$msg"
            fi
          fi
          echo "$now $written" > $state
        done
        echo "=== $(date -Iseconds) ===" >> $log
      '';
    };
  };

  systemd.timers.nvme-health-log = {
    description = "Periodic NVMe health snapshot";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "6h";
      Persistent = true;
    };
  };
}
