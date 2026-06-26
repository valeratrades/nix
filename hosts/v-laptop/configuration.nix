{ ...
}:
{
  services.ringboard.wayland.enable = true;

  # aarch64 emulation, so this x86_64 host can build the rpi5 SD image.
  # Removable: delete this line + rebuild if Pi image builds move elsewhere.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Resolve *.local (mDNS), so `ssh admin@rpi5.local` works from here.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
}
