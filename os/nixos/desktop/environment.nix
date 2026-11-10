{ pkgs, lib, user, inputs, myvars, ... }: {
  # Derived, not restated: v_flakes/langs/rs/nightly_version.nix is the fleet-wide pin, so the
  # cargo-scripts here can never drift from what the repos build against.
  # sessionVariables (not variables) so eww/systemd-user inherit it via PAM, not just login shells.
  environment.sessionVariables.DEFAULT_CARGO_NIGHTLY_VERSION = inputs.v_flakes.rs.nightly_version;

  # vars/ports.nix is the only place this number is chosen; fish is symlinked raw from the repo
  # and cannot read nix, so `clc` picks the port up from here.
  environment.sessionVariables.LITELLM_PORT = toString myvars.ports.litellm;
  environment.sessionVariables.LITELLM_MIXED_PORT = toString myvars.ports.litellmMixed;
  environment.sessionVariables.CHROME_DEBUG_PORT = toString myvars.ports.chromeDebug;

  # typst parses every system font on each start, no cache: ~0.85s for google-fonts + nerd-fonts alone.
  # Project flakes export their own TYPST_FONT_PATHS, overriding this.
  environment.sessionVariables.TYPST_IGNORE_SYSTEM_FONTS = "true";
  environment.sessionVariables.TYPST_FONT_PATHS = toString (pkgs.symlinkJoin {
    name = "typst-fonts";
    paths = with pkgs; [
      # the files `google-fonts.override { fonts = [ ... ]; }` picked, without its 2.9G whole-repo source
      (let rev = "5174b3333331c966c38f4355d50b03ca1c1df2f9"; in runCommand "google-fonts-typst" { } (lib.concatStrings (lib.mapAttrsToList (f: hash: ''
        install -Dm444 ${fetchurl {
          url = "https://raw.githubusercontent.com/google/fonts/${rev}/ofl/${builtins.replaceStrings [ "[" "]" ] [ "%5B" "%5D" ] f}";
          name = builtins.replaceStrings [ "[" "]" ] [ "" "" ] (baseNameOf f);
          inherit hash;
        }} "$out/share/fonts/truetype/${baseNameOf f}"
      '') {
          "lato/Lato-Black.ttf" = "sha256-gIxig5xi28595omvdgNmb8f4uB4N9TfYpSEsh1gNQzc=";
          "lato/Lato-BlackItalic.ttf" = "sha256-MhT3W/lng6VxvSUzjIZ8Zp58XnwIoifxintjdm1ubL4=";
          "lato/Lato-Bold.ttf" = "sha256-igqs510zeU7s5LKBh7/B3wu9KIi12KVuAXiMjWXRa+E=";
          "lato/Lato-BoldItalic.ttf" = "sha256-YsG38NLnS0WWAVTDUg78M3tVPbCWG/3JUNVhgzRZbMg=";
          "lato/Lato-ExtraBold.ttf" = "sha256-YQGN5iva+Q1KyAsdU8XBMHVsjpIZrqPSdz/JvVhpr5c=";
          "lato/Lato-ExtraBoldItalic.ttf" = "sha256-pCs4S5w3kTphAj46R8B/6tJud2Enu8nmoMlv5BMIk3Q=";
          "lato/Lato-ExtraLight.ttf" = "sha256-mJmJtIHbXfCCfZDFH9CNAk/nvE42cEbiWEoNOwSHk20=";
          "lato/Lato-ExtraLightItalic.ttf" = "sha256-/FZSYlC5tkzgkIxSNQsD6RuEr+ywj9KDShLle5Gr2zE=";
          "lato/Lato-Italic.ttf" = "sha256-45nETv4ThxAFMdJsfkgAxdEiUbiQ1mVKMJjHxnnLF4Y=";
          "lato/Lato-Light.ttf" = "sha256-zyp3RQO69BjVhPSZZ70WDh4D8IfBOyVgLygCTsd4jwg=";
          "lato/Lato-LightItalic.ttf" = "sha256-cA5nIv0UoQ52RjR6axTEhtTDZKNzumHHDgtczueBFjU=";
          "lato/Lato-Medium.ttf" = "sha256-06wYKmgz4AV0XddWefutCBwLElNd9Ok62O1XgXoxozg=";
          "lato/Lato-MediumItalic.ttf" = "sha256-7Lzmz/pC2KZ6/rJ6nW6F1RXoFIHUss7OmJ6DOkgEhAU=";
          "lato/Lato-Regular.ttf" = "sha256-1jbkaDIx+THtoiLViOlE0IK/0726AvkovuRhwPGFslE=";
          "lato/Lato-SemiBold.ttf" = "sha256-cbi33svnWoge0me+U51AK9HpQgt5lliq2k4NG9WvgDw=";
          "lato/Lato-SemiBoldItalic.ttf" = "sha256-Wt62szTY+5nvBTvAUrlSdz1UQxXg4dZooSwM6L1RN1w=";
          "lato/Lato-Thin.ttf" = "sha256-ZjxVv+mjgnD/9E2ic79NeS6vw+fhIB9iwwZMrYDF1ec=";
          "lato/Lato-ThinItalic.ttf" = "sha256-5ehuIZzmmHsXVHDZTVd1Ojh9GGC2NdpjJ6YOjRmjO+s=";
          "ebgaramond/EBGaramond-Italic[wght].ttf" = "sha256-O2gWIfnFLvPgE5VTBQCcXQD4WlDGEol6O08Yu85JBFg=";
          "ebgaramond/EBGaramond[wght].ttf" = "sha256-t/HdkWQ+T4H2DkP6nEuhF2Y6ABYhkT3P0hNwak2D5tk=";
          "spacemono/SpaceMono-Bold.ttf" = "sha256-QF5z1Br7flkG784gajJq9clW844lXzVCHCYOhh5ZnFk=";
          "spacemono/SpaceMono-BoldItalic.ttf" = "sha256-zcyV7d7jEoealyhJTllfWRyxWfPydtebxYZz3sflcTg=";
          "spacemono/SpaceMono-Italic.ttf" = "sha256-7KJkyGkKkf6DfRmmut8tiJYWEMTIqvyxllJhkqnyWMU=";
          "spacemono/SpaceMono-Regular.ttf" = "sha256-lYN+GCuu6tqDNo93SNsoNX8KG3XGuE/3Blte35M8jhg=";
        })))
      liberation_ttf
      gyre-fonts
      dejavu_fonts
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
  });

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

    CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1"; # `cl` re-enables it per-session
    CLAUDE_CODE_DISABLE_ORG_MEMORY = "1";
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
