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

  # Desktop notification on smartd events
  systemd.services.smartd-notify = {
    description = "Forward smartd alerts to desktop notification";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.libnotify}/bin/notify-send -u critical 'SMART Alert' 'Drive health warning — check smartctl'";
    };
  };

  # Also log unsafe shutdown count so we can track the trend
  systemd.services.nvme-health-log = {
    description = "Log NVMe health snapshot";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nvme-health-log" ''
        ${pkgs.smartmontools}/bin/smartctl -A /dev/nvme0n1 2>&1 | ${pkgs.gnugrep}/bin/grep -E '(Media|Error|Unsafe|Warning|Critical|Available Spare)' >> /var/log/nvme-health.log
        echo "---" >> /var/log/nvme-health.log
        ${pkgs.smartmontools}/bin/smartctl -A /dev/nvme1n1 2>&1 | ${pkgs.gnugrep}/bin/grep -E '(Media|Error|Unsafe|Warning|Critical|Available Spare)' >> /var/log/nvme-health.log
        echo "=== $(date -Iseconds) ===" >> /var/log/nvme-health.log
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
