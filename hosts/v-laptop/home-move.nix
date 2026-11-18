# One-shot move of nix#28: on the first boot with /home on nvme1p2, before any login, takes the final copy off the old
# ext4 /home (nvme0p3), reformats it as XFS and fills it with ~/s, ~/.cargo and the kache store. Delete once #28 is closed.
{ pkgs, ... }:
let
  oldHome = "271e936a-178b-4d50-96c8-16114b4022d3";
  newHome = "01557177-a418-4348-9646-795fd53521e6";
  xfs = "6bed86da-29e5-41db-b87e-8c131e86a415";
  move = pkgs.writeShellApplication {
    name = "home-move";
    runtimeInputs = with pkgs; [ rsync util-linux xfsprogs coreutils systemd gnugrep ];
    text = ''
      if [ "$(findmnt -n -o FSTYPE /home/v/s | tail -n1)" = xfs ]; then
        echo "home-move: /home/v/s is already XFS"
        exit 0
      fi
      [ "$(findmnt -n -o UUID /home | tail -n1)" = ${newHome} ] || { echo "home-move: /home is not nvme1p2"; exit 1; }
      dev=$(readlink -f /dev/disk/by-uuid/${oldHome})
      [ "$dev" = /dev/nvme0n1p3 ] || { echo "home-move: old /home resolved to '$dev'"; exit 1; }
      for l in /home/v/.cargo /home/v/.cache/kache; do
        [ ! -e "$l" ] || [ -L "$l" ] || { echo "home-move: $l exists as a real path"; exit 1; }
      done

      R=(rsync -aHAXS --numeric-ids --delete)
      mkdir -p /mnt/oldhome /home/.hold/s /home/.hold/cargo /home/.hold/kache
      mount -o ro "$dev" /mnt/oldhome
      "''${R[@]}" --exclude=/v/s/ --exclude=/v/.cargo/ --exclude=/v/.cache/kache/ --exclude='/v/.config/google-chrome-cdp/*' \
        --exclude=/.hold/ --exclude=/lost+found/ /mnt/oldhome/ /home/
      "''${R[@]}" /mnt/oldhome/v/s/ /home/.hold/s/
      "''${R[@]}" /mnt/oldhome/v/.cargo/ /home/.hold/cargo/
      "''${R[@]}" /mnt/oldhome/v/.cache/kache/ /home/.hold/kache/
      umount /mnt/oldhome

      mkfs.xfs -f -L s -m uuid=${xfs} "$dev"
      udevadm settle
      mkdir -p /home/v/s
      mount -t xfs -o noatime /dev/disk/by-uuid/${xfs} /home/v/s
      "''${R[@]}" /home/.hold/s/ /home/v/s/
      "''${R[@]}" /home/.hold/cargo/ /home/v/s/.cargo/
      "''${R[@]}" /home/.hold/kache/ /home/v/s/.kache/
      ln -sfn /home/v/s/.cargo /home/v/.cargo
      ln -sfn /home/v/s/.kache /home/v/.cache/kache
      chown -h v:users /home/v/.cargo /home/v/.cache/kache
      echo "home-move: done; /home/.hold kept until verified"
    '';
  };
in
{
  boot.supportedFilesystems = [ "xfs" ];
  systemd.services.home-move = {
    description = "nix#28: final /home copy, nvme0p3 to XFS for ~/s";
    wantedBy = [ "multi-user.target" ];
    requiredBy = [ "systemd-user-sessions.service" "user@1000.service" ]; # a failed move keeps everyone but root out; v lingers, so user@1000 starts without a login
    before = [ "systemd-user-sessions.service" "user@1000.service" "home-manager-v.service" ];
    after = [ "local-fs.target" ];
    unitConfig.RequiresMountsFor = "/home";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "infinity";
      StandardOutput = "journal+console";
      ExecStart = "${move}/bin/home-move";
    };
  };
}
