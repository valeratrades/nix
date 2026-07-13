{ self, config, lib, pkgs, user, inputs, ... }: {
  imports = [
    ./programs
    ./claude.nix
    ./nixcord.nix
    (
      # in my own config I symlink stuff to fascilitate experimentation. In derived setups I value reproducibility much more
      if user.symlinkConfigs == true then
        ./config_symlinks.nix
      else
        (import ./config_writes.nix { inherit self pkgs user; }))
    # Import desktop services only for non-server users
    (if user.userFullName != "Server" then ./desktop-services.nix else null)
  ];
  #dbg: look at comment in ./config_symlinks.nix

  programs = {
    neovim = {
      plugins = [
        pkgs.vimPlugins.nvim-treesitter.withAllGrammars # can also choose specific ones with `.withPlugins (p: [ p.c p.java /*etc*/ ]))`
      ];
      defaultEditor = true; # sets $EDITOR
      #? Can I get a nano alias?
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
    };

    direnv = {
      enable = true;
      enableFishIntegration = true;
      package = pkgs.direnv;
      nix-direnv = {
        enable = true; # faster on nix
        # _nix_clean_old_gcroots uses pattern `{nix,flake}-profile*` which matches `flake-tmp-profile.*`,
        # deleting the tmp profile before _nix_add_gcroot can create the GC root symlink.
        # Result: "error: getting status of '.direnv/flake-tmp-profile.XXX': No such file or directory"
        # Caching still works, but GC root isn't created, so dependencies get deleted on nix-collect-garbage.
        #WAIT: https://github.com/nix-community/nix-direnv/issues/546
        #WAIT: https://github.com/direnv/direnv/issues/1181
        package = pkgs.nix-direnv.overrideAttrs (old: {
          postFixup = (old.postFixup or "") + ''
            substituteInPlace $out/share/nix-direnv/direnvrc \
              --replace-fail '{nix,flake}-profile*' '{nix-profile-,flake-profile-}*' \
              --replace-fail '_nix build --out-link "$symlink" "$storepath"' '_nix build --out-link "$symlink" "$(readlink -f "$storepath")"'
          '';
        });
      };
      silent = true;
      # Any existing nix-direnv cache is used as-is: no re-evaluation, no network,
      # even if flake.{nix,lock} changed. `nix-direnv-reload` (`dirr`) is the only
      # way to update. A project with no cache at all still evaluates automatically
      # (stock nix_direnv_manual_reload would just warn and leave you with no env).
      # See ongoing_debug/2026-07-11_nix-develop-direnv-offline.md
      stdlib = ''
        if compgen -G "$(direnv_layout_dir)/*-profile-*.rc" >/dev/null; then
          _nix_direnv_manual_reload=1
        fi
      '';
    };

    eza.enable = true;
    yazi.enable = true;
    # ref tmux config: https://github.com/Dich0tomy/snowstorm/blob/trunk/modules/home/tmux/default.nix
    tmux = {
      enable = true; # dbg
      keyMode = "vi";
      shortcut = "e";
      # Build tmux WITHOUT systemd integration. With it (nixpkgs default
      # withSystemd=true), tmux places every pane in its own systemd scope
      # (tmux-spawn-*.scope). That scope creation fails — "Couldn't move process
      # … Permission denied" (319+ times in the journal) — leaving the scope in a
      # broken cgroup state. At shutdown, systemd's control-group SIGTERM can't
      # reach the process, so the scope rides out its full stop timeout before
      # SIGKILL — THE slow-shutdown bug. Without systemd, panes are plain children
      # of the tmux server and get killed cleanly.
      # See ongoing_debug/2026-06-05_slow-shutdown.md.
      package = pkgs.tmux.override { withSystemd = false; };
      plugins = with pkgs; [
        #tmuxPlugins.resurrect # persist sessions
        tmuxPlugins.open # open files
        tmuxPlugins.copycat # enables regex

        # [To save]: <prefix> + C-s
        {
          plugin = tmuxPlugins.resurrect;
          extraConfig = "set -g @resurrect-strategy-nvim 'session'";
        }
      ];
      extraConfig = "${self}/home/config/tmux/tmux.conf";
    };
    home-manager.enable = true; # let it manage itself
  };

  xdg.desktopEntries."com.obsproject.Studio" = {
    name = "OBS";
    genericName = "Streaming/Recording Software";
    comment = "Free and Open Source Streaming/Recording Software";
    exec = "obs";
    icon = "com.obsproject.Studio";
    terminal = false;
    type = "Application";
    categories = [ "AudioVideo" "Recorder" ];
    startupNotify = true;
    settings.StartupWMClass = "obs";
    settings.Keywords = "obs;studio;streaming;recording;";
  };

  dconf = {
    enable = true;
    settings."org/gnome/desktop/interface" = { color-scheme = "prefer-dark"; };
  };

  gtk = {
    enable = true;
    theme = {
      name = "Materia-dark"; # dbg: want Adwaita-dark
      package = pkgs.materia-theme;
    };
    gtk4.theme = config.gtk.theme;
  };

  #REF: example of working service setup here: https://github.com/nix-community/home-manager/blob/master/modules/services/polybar.nix

  # Create a sway-session target that can be manually started
  systemd.user.targets.sway-session = {
    Unit = {
      Description = "Sway compositor session";
      Documentation = "man:systemd.special(7)";
      BindsTo = [ "graphical-session.target" ];
      Wants = [ "graphical-session-pre.target" ];
      After = [ "graphical-session-pre.target" ];
    };
  };

  systemd.user.services.eww-widgets = {
    Unit = {
      Description = "Start Eww Widgets";
      After = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };
    Install = { WantedBy = [ "sway-session.target" ]; };
    Service = let
      eww = "${pkgs.eww}/bin/eww";
      script = pkgs.writeShellScript "eww-widgets-start" ''
        ${eww} open bar
        ${eww} open btc_line_lower
        ${eww} open btc_line_upper
        ${eww} open todo_blocker
      '';
    in {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${script}";
    };
  };

  systemd.user.services.wlr-gamma = {
    Unit = {
      Description = "wlroots Brightness Control";
      PartOf = "graphical-session.target";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
    Service = {
      Type = "simple";
      ExecStart = "${
          self.packages.${pkgs.stdenv.hostPlatform.system}.wlr-gamma-service
        }/bin/wlr-gamma-service";
    };
  };
  systemd.user.services.mpris-proxy = {
    Unit = {
      Description = "Forward bluetooth AVRCP media buttons to MPRIS";
      After = [ "network.target" "sound.target" ];
      PartOf = "graphical-session.target";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
    };
  };
  systemd.user.services.ssh-add-ed25119 = {
    Unit = { PartOf = "multi-user.target"; };
    Install = { WantedBy = [ "default.target" ]; };
    Service = {
      Type = "simple";
      ExecStart = "ssh-add ${config.home.homeDirectory}/.ssh/id_ed25519";
    };
  };

  auto_redshift = {
    enable = true;
    wakeTime = user.wakeTime;
  };

  home = {
    #FIXME: doesn't seem to work //Q: could it be because I have `fish.enable` inside the main configuration.nix, which overwrites this clean?
    sessionPath = [
      #"${pkgs.lib.makeBinPath [ ]}"
      "${config.home.homeDirectory}/s/evdev/"
      "${config.home.homeDirectory}/.cargo/bin/"
      "${config.home.homeDirectory}/go/bin/"
      "/usr/lib/rustup/bin/"
      "${config.home.homeDirectory}/.local/bin/"
      "${config.home.homeDirectory}/pkg/packages.modular.com_mojo/bin"
      "${config.home.homeDirectory}/.local/share/flatpak"
      "/usr/bin"
      "/var/lib/flatpak"
    ];
    pointerCursor = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      x11 = {
        enable = true;
        defaultCursor = "Adwaita";
      };
    };
    keyboard = null; # otherwise it overwrites my semimak

    # Things that never need to be available with sudo
    packages = with pkgs;
    # INFO: arrays are always automatically merged, in host-specfic `home.nix`s it may seem like I'm overwriting this, but it only looks this way.
      lib.lists.flatten [
        [
          # funsies
          unimatrix
          cowsay
          xdotool # most options don't work on wayland though
          wlrctl # wayland mouse/keyboard emulation for sway
          wtype # wl-clipboard-compatible xdotool type for Wayland (used by speech-to-text)
          playerctl # MPRIS CLI; drives XF86AudioPlay / $mod+F5 media bindings in sway
          whisper-cpp # local STT via whisper-cli (speech mode driver "w")
        ]
        [
          # messengers
          # Wrap telegram-desktop to force XDG portal usage for file dialogs
          # (global QT_QPA_PLATFORMTHEME doesn't get picked up by Telegram)
          (runCommand "telegram-desktop-portal" { nativeBuildInputs = [ makeWrapper ]; } ''
            mkdir -p $out/bin $out/share/applications $out/share/icons
            ln -s ${telegram-desktop}/share/icons/* $out/share/icons/
            makeWrapper ${telegram-desktop}/bin/Telegram $out/bin/Telegram \
              --set QT_QPA_PLATFORMTHEME xdgdesktopportal
            ln -s $out/bin/Telegram $out/bin/telegram-desktop
            # Patch desktop file to use our wrapped binary
            substitute ${telegram-desktop}/share/applications/org.telegram.desktop.desktop \
              $out/share/applications/org.telegram.desktop.desktop \
              --replace-fail "Exec=Telegram" "Exec=$out/bin/Telegram"
          '')
          element-desktop # GUI matrix client
          #iamb # TUI matrix client (rust) #dbg: broken in nixpkgs - type recursion limit in matrix-sdk
          zulip
        ]
        [
          # Desktop/GUI packages moved from configuration.nix
          libinput-gestures
          #qt5.full #dbg: brings in qtwebengine, which builds for too long
          (google-chrome.override {
            commandLineArgs = [
              # Re-enabled GPU video accel: CPU decode pegged renderers at ~190% and
              # baked the package to 80°C. Encode stays off (more crash-prone than decode).
              "--disable-accelerated-video-encode"
              "--silent-debugger-extension-api" # suppress OpenClaw Auto Relay debug bar
              "--remote-debugging-port=49300" # 9222 normally, but that's default, so some tools choose it to, and then end up messing with my ongoing session
              # Block silent ~4GB Gemini Nano (weights.bin under OptGuideOnDeviceModel)
              # download. Disables the optimization-guide on-device model + its downloader.
              "--disable-features=OptimizationGuideOnDeviceModel,OptimizationGuideModelDownloading,TextSafetyClassifier,OnDeviceModelPerformanceParams"
              # Allow extensions (Vimium etc.) to inject into chrome:// pages and the NTP.
              # Chrome Web Store remains blocked (separate hardcoded restriction).
              "--extensions-on-chrome-urls"
              # Stop Google's server-side Finch/Variations from remote-toggling features
              # mid-day without our consent (UI redesigns, extension restrictions, etc.).
              "--disable-field-trial-config"
              "--variations-server-url="
              # Stop Chrome's Component Updater from pulling things outside nix
              # (incl. AI model weights, side-channel updates).
              "--disable-component-update"
              # Chrome blocks the debug port when --user-data-dir canonicalizes to the
              # default profile path. google-chrome-cdp is a bind mount of the real
              # profile (os/nixos/desktop/services/chrome-cdp.nix) — a distinct path
              # identity that readlink -f does NOT resolve back to the default, so CDP
              # opens while we keep using the one real profile underneath.
              "--user-data-dir=${config.home.homeDirectory}/.config/google-chrome-cdp"
              # Diagnostics for a recurring browser-main-thread SIGSEGV (NULL deref at
              # a fixed instruction, identical stack across crashes) on the CDP instance.
              # GUI launch has no usable stderr, so log to a file that survives the crash;
              # pair with the Crashpad minidump to find the DevTools command that triggers it.
              "--enable-logging"
              "--log-file=${config.home.homeDirectory}/.config/google-chrome-cdp/chrome_debug.log"
              "--v=1"
            ];
          })
          alacritty
        ]
        [
          # Terminal apps/scripts (actually useful)
          typioca # tui monkeytype
          smassh # tui monkeytype
          fastfetch
          figlet
        ]
        [
          # nix
          nix-tree # analyse nix-store
        ]
        [
          # zathura
          zathura 
          zathuraPkgs.zathura_pdf_poppler
          zathuraPkgs.zathura_cb
          zathuraPkgs.zathura_pdf_mupdf
          zathuraPkgs.zathura_djvu
          zathuraPkgs.zathura_ps
        ]
        [
          # RDP clients (linux-to-linux doesn't really work)
          remmina
          anydesk # works to manage windows/linux+X11, but obviously can't RDP linux running wayland
          freerdp
        ]
        [
          # auth
          oath-toolkit # https://askubuntu.com/questions/1460640/generating-totp-for-2fa-directly-from-the-computer-no-mobile-device
          bitwarden-desktop # seems like bitwarden is lacking TOTP on free plans
          bitwarden-cli
          keepassxc
          #TODO: attempt to maybe start using it. Or just go agenix/sops. Current system is rather fragile. Priority is low because currently there isn't much to protect.
          pass # linux password manager
          prs # some password manager in rust
          passh # non-interactive SSH auth
        ]
        eww # info bar
        rnote # graphical notes
        qbittorrent # BitTorren gui
        transmission_4 # BitTorrent cli
        dragon-drop # drag-and-drop for X11 only
        neomutt # email client
        himalaya # email client but in rust
        fswebcam # instant webcam photo
        anyrun # wayland-native rust alternative to rofi
        pdfgrep
        xournalpp # draw on PDFs
      ] ++ [
        inputs.auto_redshift.packages.${pkgs.stdenv.hostPlatform.system}.default # good idea for everyone
        (inputs.tedi.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: { doCheck = false; })) # pretty generic at this point
        inputs.bbeats.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.math_tools.packages.${pkgs.stdenv.hostPlatform.system}.default # could be useful to all people currently using my distro
        inputs.reasonable_envsubst.packages.${pkgs.stdenv.hostPlatform.system}.default # have scripts depending on it, and they are currently part of the shared config.
        inputs.booktyping.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];

    activation = {
      # # my file arch consequences
      mkdir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/tmp/
        mkdir -p $HOME/tmp/msg_drafts/
        mkdir -p $HOME/Videos/obs/
        mkdir -p $HOME/tmp/Screenshots/
      '';
      #
    };
    file = {
      # # fs
      "g/README.md".source = "${self}/home/fs/g/README.md$";
      "s/g/README.md".source = "${self}/home/fs/s/g/README.md";
      "s/l/README.md".source = "${self}/home/fs/s/l/README.md";
      "s/tmp/README.md".source = "${self}/home/fs/s/tmp/README.md";
      "tmp/README.md".source = "${self}/home/fs/tmp/README.md";
      "tmp/msg_drafts/README.md".source = "${self}/home/fs/tmp/msg_drafts/README.md";
      #

      # upgradeQ/obs-filter-hotkeys lua scripts (add via OBS Tools > Scripts)
      ".config/obs-studio/scripts/filter_hotkeys_video.lua".source =
        "${self}/home/config/obs-studio/scripts/filter_hotkeys_video.lua";
      ".config/obs-studio/scripts/filter_hotkeys_audio.lua".source =
        "${self}/home/config/obs-studio/scripts/filter_hotkeys_audio.lua";
      # Declarative filter settings, pushed to OBS via obs-websocket by obs-update-filters
      ".config/obs-studio/filter_settings.nix".source =
        "${self}/home/config/obs-studio/filter_settings.nix";

      ".config/tg_admin.toml".source = "${self}/home/config/tg_admin.toml";
      ".config/auto_redshift.toml".source = "${self}/home/config/auto_redshift.toml";
      ".config/tedi.nix".source = "${self}/home/config/tedi.nix";

      ".lesskey".source = "${self}/home/config/lesskey";

      # Compose-key sequences. `include "%L"` pulls in the system defaults so
      # standard compose bindings keep working; entries below extend them.
      ".XCompose".text = ''
        include "%L"

        <Multi_key> <e> <i> : "∈" U2208 # ELEMENT OF
        <Multi_key> <n> <i> : "∉" U2209 # NOT AN ELEMENT OF
        
        <Multi_key> <g> <s> : "σ" U03C3
        <Multi_key> <g> <S> : "Σ" U03A3
      '';
      ".config/fish/conf.d/sway.fish".source =
        "${self}/home/config/fish/conf.d/sway.fish";

      ".config/iamb/config.toml".source = (pkgs.formats.toml { }).generate "" {
        default_profile = "master";
        profiles = {
          master = { user_id = "@${user.defaultUsername}:matrix.org"; };
        };
        macros = {
          normal = {
            s = "h";
            r = "j";
            n = "k";
            t = "l";

            gc = ":chats<Enter>";
            gd = ":dms<Enter>";
            gr = ":reply<Enter>";
            eh = ":react! heart<Enter>";
            eu = ":react! up<Enter>";
            ed = ":react! down<Enter>";

            "<M-c>" = "<C-w>q";
            "<C-w>v" = ":vsplit #alias:example.com<Enter>";
            "<C-w>h" = ":split #alias:example.com<Enter>";
          };
          command = { help = "welcome<Enter>"; };
        };
      };

      # Configure xdg-desktop-portal to use termfilechooser
      ".config/xdg-desktop-portal/sway-portals.conf".text = ''
        [preferred]
        default=gtk
        org.freedesktop.impl.portal.FileChooser=termfilechooser
      '';

      # xdg-desktop-portal-termfilechooser wrapper script
      ".config/xdg-desktop-portal-termfilechooser/termfilechooser.sh".source = ../../home/config/filechooser/termfilechooser.sh;

      # xdg-desktop-portal-termfilechooser config
      ".config/xdg-desktop-portal-termfilechooser/config".text = ''
        [filechooser]
        cmd = termfilechooser.sh
      '';

      #TODO: figure out  (they have some bug on their side at the moment)
      #".config/direnv/direnv.toml".source = (pkgs.formats.toml { }).generate "" {
      #  global = {
      #    # https://github.com/direnv/direnv/issues/68#issuecomment-2054033048
      #    hide_env_diff = true;
      #  };
      #};

      #BUG: stupid `atuin` overwrites my generated config with a dummy one
      #dbg: \
       ".config/atuin/config.toml".source =
         (pkgs.formats.toml { }).generate "atuin.toml" (import "${self}/home/config/atuin.nix");

      # configured via hm, can't just symlink it in my host's config
      ".config/tmux" = {
        source = "${self}/home/config/tmux";
        recursive = true;
      };

      ".cargo/rustfmt.toml".source = "${self}/home/config/cargo/rustfmt.toml";
      ".cargo/config.toml".source = (pkgs.formats.toml { }).generate "cargo-config.toml" ({
        profile = {
          release = { debug = 0; opt-level = 2; };
          dev = { debug = true; };
          dev.package = {
            v_utils = { opt-level = 1; };
            bevy = { opt-level = 3; };
            bevy_editor_pls = { opt-level = 3; };
            bevy_panorbit_camera = { opt-level = 3; };
            insta = { opt-level = 3; };
          };
        };
        alias =
          let
            nextest = "nextest run --workspace";
            clippy_fix = "clippy --fix --allow-dirty --allow-no-vcs";
          in
          {
          w = "watch";
          a = "add";
          u = "update";
          m = "machete";
          re = "insta review";
          rt = "insta test --review";
          f = "fmt";
          xc = "${clippy_fix}";
          xca = "${clippy_fix} --all-targets --all-features --allow-staged";
          s = "sweep --recursive --installed";
          rel = "release --no-confirm --execute";
          so = "sort -wg";
          b = "lbuild";
          c = "lcheck";
          r = "lrun";
          t = "${nextest}";
          te = "${nextest} --examples";
          ta = "${nextest} --no-fail-fast";
          ls = "leptos serve";
          lw = "leptos watch --hot-reload";
        };
        cargo-new = { vcs = "none"; };
      } // lib.optionalAttrs (user ? sccache && user.sccache) {
        build = { rustc-wrapper = "sccache"; };
      } // {
        # rustup on NixOS bakes the nix store path of ld-wrapper.sh into the toolchain's ld.lld script.
        # That path goes stale on every rustup package update, breaking `cargo install`.
        # This bypasses the wrapper entirely, using the stable system lld path instead.
        # Project-level .cargo/config.toml overrides this, so nix develop envs stay unaffected.
        target."x86_64-unknown-linux-gnu" = {
          linker = "clang";
          rustflags = ["-C" "link-arg=-fuse-ld=/run/current-system/sw/bin/ld.lld"];
        };
      });
			".config/zathura" = {
				source = "${self}/home/config/zathura";
				recursive = true;
			};
			".config/keyd" = {
				source = "${self}/home/config/keyd";
				recursive = true;
			};
			".config/mako" = {
				source = "${self}/home/config/mako";
				recursive = true;
			};
			".config/wireplumber" = {
				source = "${self}/home/config/wireplumber";
				recursive = true;
			};
		};
	};

	# Force obs-websocket server enabled. OBS rewrites this file on shutdown,
	# so we patch it on every home-manager generation rather than symlinking.
	# Used by sway obs-mode `f` keybind to toggle the camera blur filter.
	home.activation.obsWebsocketEnable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
		cfg="${config.home.homeDirectory}/.config/obs-studio/plugin_config/obs-websocket/config.json"
		if [ -f "$cfg" ]; then
			tmp=$(mktemp)
			${pkgs.jq}/bin/jq '.server_enabled = true' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
		fi
	'';
}
