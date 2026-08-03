{ ...
}:
{
  services.ringboard.wayland.enable = true;

  # aarch64 emulation, so this x86_64 host can build the rpi5 SD image.
  # Removable: delete this line + rebuild if Pi image builds move elsewhere.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Physical cores 12-15, with their SMT siblings 28-31, held out of PID 1's affinity — which every
  # unit and login session inherits, so nothing lands there unless it asks by name. `BENCH_CPUS` in
  # ev_invest/trading_data asks; a wall-clock number taken on a shared core measures the scheduler.
  #
  # This is 8 of 32 threads gone from everything else, permanently — a 32-thread `cargo b` becomes 24.
  # Delete the line to take them back; takes effect on `systemctl daemon-reexec` or reboot. The set is
  # deliberately the top four cores: `lscpu -e` pairs CPU n with n+16, and splitting a pair would
  # reserve a thread whose sibling is still contended, which measures nothing.
  systemd.settings.Manager.CPUAffinity = "0-11 16-27";

  # Resolve *.local (mDNS), so `ssh admin@rpi5.local` works from here.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
}
