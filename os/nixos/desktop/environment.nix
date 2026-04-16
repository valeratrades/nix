{ pkgs, user, ... }: {
  environment.variables = {
    QT_QPA_PLATFORMTHEME = "xdgdesktopportal";
    GTK_USE_PORTAL = "1";
    GDK_DEBUG = "portals";
    DEFAULT_BROWSER = "${pkgs.google-chrome}/bin/google-chrome-stable";
    WINEPREFIX = "/home/${user.username}/.wine";
    # Use AMD iGPU for VA-API video acceleration (radeonsi, stable on Wayland)
    # NVIDIA dGPU was crash-prone so we keep it off; AMD handles decoding instead
    LIBVA_DRIVER_NAME = "radeonsi";
    VDPAU_DRIVER = "radeonsi";
    __GL_FSAA_MODE = "0";        # disable antialiasing
    __GL_LOG_MAX_ANISO = "0";    # disable anisotropic filtering
    # claude code (https://github.com/anthropics/claude-code/issues/42796#issuecomment-4194007103)
    DISABLE_TELEMETRY = "1";
    CLAUDE_CODE_DISABLE_1M_CONTEXT = "1";
    CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1";
    MAX_THINKING_TOKENS = 63999;
  };

  systemd.services.hibernate-prepare = {
    description = "Prepare for hibernate by killing memory-heavy processes";
    # Must run before nvidia-hibernate so GPU clients are dead when nvidia saves VRAM state
    before = [ "systemd-hibernate.service" "systemd-suspend-then-hibernate.service" "nvidia-hibernate.service" ];
    requiredBy = [ "systemd-hibernate.service" "systemd-suspend-then-hibernate.service" ];
    serviceConfig = {
      Type = "oneshot";
    };
    path = [ pkgs.procps pkgs.socat pkgs.coreutils ];
    script = ''
      # Kill memory-heavy processes before hibernate to minimize image size.
      # The kernel's hibernate writer is single-threaded synchronous IO at 228 MB/s,
      # so every GB we avoid snapshotting saves ~4.5s of wall time.

      # LSPs (~5 GB combined) - nvim restarts them on demand
      pkill -f 'lua-language-server' || true
      pkill -f 'rust-analyzer' || true
      pkill -f 'rust-analyzer-proc-macro-srv' || true

      # Browsers (~3 GB combined) - session restore handles state
      pkill -f 'chrome' || true
      pkill -f 'firefox' || true

      # Services that restart losslessly
      pkill -f 'openclaw-gateway' || true
      pkill -f 'tailscaled' || true
      pkill -f 'clickhouse' || true

      # Gracefully shut down QEMU VM (~2 GB)
      echo 'system_powerdown' | socat - TCP:localhost:7100 || true
      sleep 5
      pkill -f 'qemu-system' || true

      # Drop filesystem caches right before snapshot
      sync
      echo 3 > /proc/sys/vm/drop_caches
    '';
  };

  systemd.services.hibernate-resume = {
    description = "Restart services after hibernate resume";
    after = [ "systemd-hibernate.service" "systemd-suspend-then-hibernate.service" ];
    requiredBy = [ "systemd-hibernate.service" "systemd-suspend-then-hibernate.service" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
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
