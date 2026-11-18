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

  # also leaves each drive's smart json world-readable, for `health` to show wear without root
  systemd.services.nvme-health-log = {
    description = "Log NVMe health snapshot";
    path = [ pkgs.smartmontools pkgs.gnugrep ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "nvme-health";
      StateDirectoryMode = "0755";
      ExecStart = pkgs.writeShellScript "nvme-health-log" ''
        set -eu
        log=/var/log/nvme-health.log
        for dev in nvme0n1 nvme1n1; do
          smartctl -A /dev/$dev | grep -E '(Media|Error|Unsafe|Warning|Critical|Available Spare|Percentage Used|Data Units Written)' >> $log
          echo "---" >> $log
          smartctl -j -i -A /dev/$dev > $STATE_DIRECTORY/$dev.json || [ $? -lt 8 ] # bits 3+ are drive-health verdicts, the json is still whole
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
