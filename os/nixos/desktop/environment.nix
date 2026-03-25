{ pkgs, user, ... }: {
  environment.variables = {
    QT_QPA_PLATFORMTHEME = "xdgdesktopportal";
    GTK_USE_PORTAL = "1";
    GDK_DEBUG = "portals";
    DEFAULT_BROWSER = "${pkgs.google-chrome}/bin/google-chrome-stable";
    WINEPREFIX = "/home/${user.username}/.wine";
    # dbg: disable GPU acceleration everywhere to test if GPU is causing crashes
    LIBVA_DRIVER_NAME = "null";  # disable VA-API (video acceleration)
    VDPAU_DRIVER = "none";       # disable VDPAU
    __GL_FSAA_MODE = "0";        # disable antialiasing
    __GL_LOG_MAX_ANISO = "0";    # disable anisotropic filtering
  };

  powerManagement = {
    powerDownCommands = ''
      # Kill memory-heavy processes before hibernate to minimize image size.
      # The kernel's hibernate writer is single-threaded synchronous IO at 228 MB/s,
      # so every GB we avoid snapshotting saves ~4.5s of wall time.

      # LSPs (~5 GB combined) - nvim restarts them on demand
      ${pkgs.procps}/bin/pkill -f 'lua-language-server' || true
      ${pkgs.procps}/bin/pkill -f 'rust-analyzer' || true
      ${pkgs.procps}/bin/pkill -f 'rust-analyzer-proc-macro-srv' || true

      # Browsers (~3 GB combined) - session restore handles state
      ${pkgs.procps}/bin/pkill -f 'chrome' || true
      ${pkgs.procps}/bin/pkill -f 'firefox' || true

      # Services that restart losslessly
      ${pkgs.procps}/bin/pkill -f 'openclaw-gateway' || true
      ${pkgs.procps}/bin/pkill -f 'tailscaled' || true
      ${pkgs.procps}/bin/pkill -f 'clickhouse' || true

      # Gracefully shut down QEMU VM (~2 GB)
      echo 'system_powerdown' | ${pkgs.socat}/bin/socat - TCP:localhost:7100 || true
      ${pkgs.coreutils}/bin/sleep 5
      ${pkgs.procps}/bin/pkill -f 'qemu-system' || true

      # Drop filesystem caches right before snapshot
      ${pkgs.coreutils}/bin/sync
      echo 3 > /proc/sys/vm/drop_caches
    '';
    powerUpCommands = ''
      systemctl restart tailscaled || true
      systemctl restart clickhouse || true
      systemctl --user -M v@ restart wlr-gamma || true
      systemctl --user -M v@ restart auto_redshift || true
    '';
  };

  # Disable all PCI wakeup sources — only lid switch and power button (ACPI) should wake from hibernate.
  # Without this, USB controllers, GPU, WiFi, NVMe, and ethernet can all trigger spurious wakeups.
  systemd.services.disable-acpi-wakeup = {
    description = "Disable PCI ACPI wakeup sources";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for dev in GPP0 GPP1 GPP3 GPP5 GP17 XHC0 XHC1 XHC2; do
        if grep -q "$dev.*enabled" /proc/acpi/wakeup; then
          echo "$dev" > /proc/acpi/wakeup
        fi
      done
    '';
  };

  system.activationScripts.copyAlacrittyConfig = {
    text = ''
      # Copy the alacritty config and set permissions
      cp /home/${user.username}/.config/alacritty/alacritty.toml.hm /home/${user.username}/.config/alacritty/alacritty.toml
      chmod 0666 /home/${user.username}/.config/alacritty/alacritty.toml
    '';
    deps = [ ];
  };
}