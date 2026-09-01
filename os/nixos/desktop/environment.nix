{ pkgs, lib, user, inputs, myvars, ... }: {
  # Derived, not restated: v_flakes/rs/nightly_version.nix is the fleet-wide pin, so the
  # cargo-scripts here can never drift from what the repos build against.
  # sessionVariables (not variables) so eww/systemd-user inherit it via PAM, not just login shells.
  environment.sessionVariables.DEFAULT_CARGO_NIGHTLY_VERSION = inputs.v_flakes.rs.nightly_version;

  # vars/ports.nix is the only place this number is chosen; fish is symlinked raw from the repo
  # and cannot read nix, so `clc` picks the port up from here.
  environment.sessionVariables.LITELLM_PORT = toString myvars.ports.litellm;
  environment.sessionVariables.LITELLM_MIXED_PORT = toString myvars.ports.litellmMixed;

  environment.variables = {
    QT_QPA_PLATFORMTHEME = "xdgdesktopportal";
    GTK_USE_PORTAL = "1";
    GDK_DEBUG = "portals";
    DEFAULT_BROWSER = "${pkgs.google-chrome}/bin/google-chrome-stable";
    WINEPREFIX = "/home/${user.username}/.wine";
    __GL_FSAA_MODE = "0";        # disable antialiasing
    __GL_LOG_MAX_ANISO = "0";    # disable anisotropic filtering

# claude code (https://github.com/anthropics/claude-code/issues/42796#issuecomment-4194007103) {{{1
    DISABLE_TELEMETRY = "1";
    # NB: CLAUDE_CODE_DISABLE_1M_CONTEXT would hard-zero the `[1m]` model suffix (cli's is1M() short-circuits
    # on it), collapsing the window to 200k and min()'ing autoCompactWindow down with it.
    # See ongoing_debug/2026-08-04_claude-1m-context-compacting-at-200k.md

    # starting from 4.8, adaptive thinking is the native model. Hopefully, it's somewhat working now. If not, - fuck it, downgrade.
    #CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1";
    #MAX_THINKING_TOKENS = 63999;

    CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1";
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"; # serveys and shit
#,}}}1
    UV_MALWARE_CHECK = "1"; # may become default in the future, - deprecate when it is

    # GPU video decode for browsers (db0a13fc, 2026-04-14): route VA-API/VDPAU to the AMD iGPU
    # (radeonsi, stable on Wayland). System-wide, so this covers Chrome/Chromium too, not just Firefox.
    # NVIDIA dGPU was crash-prone so we keep it off; AMD handles decoding instead.
    # NOT gated on user.gpuAcceleration: a fixed-function decode block costs far less power than
    # software-decoding the same stream on the CPU, so gating this made the thin chassis *hotter*.
    LIBVA_DRIVER_NAME = "radeonsi";
    VDPAU_DRIVER = "radeonsi";
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
      # openclaw gateway resumes losslessly (state in ~/.openclaw); kill it to shrink the image.
      # NB: the worker process renames its argv[0] to `openclaw-gateway`, so match on that.
      ${lib.optionalString user.openclaw "pkill -f 'openclaw-gateway' || true"}
      pkill -f 'tailscaled' || true
      ${lib.optionalString user.clickhouse "pkill -f 'clickhouse' || true"}

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
      ${lib.optionalString user.clickhouse "systemctl restart clickhouse || true"}
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
