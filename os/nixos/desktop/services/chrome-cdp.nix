{ ... }:
{
  # Chrome refuses --remote-debugging-port when --user-data-dir canonicalizes to
  # the default profile path (~/.config/google-chrome). A symlink doesn't help:
  # Chrome runs readlink -f and sees the default. A *bind mount* does — a
  # mountpoint keeps its own path identity (readlink -f of a bind target returns
  # the target, not the source), so Chrome sees a non-default path and opens CDP,
  # while still reading/writing the one real profile underneath.
  #
  # Chrome launches with --user-data-dir=~/.config/google-chrome-cdp (see
  # hm-shared/home.nix); that path is this mountpoint. systemd creates the
  # mountpoint directory itself, so no symlink/activation step is needed.
  fileSystems."/home/v/.config/google-chrome-cdp" = {
    device = "/home/v/.config/google-chrome";
    fsType = "none";
    options = [ "bind" "x-systemd.requires-mounts-for=/home/v/.config/google-chrome" ];
  };
}
