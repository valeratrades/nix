{
  self,
  pkgs,
  mylib,
  ...
}:
{
  imports = mylib.scanPaths ./.;

  # appends to existing if any
  environment.systemPackages =
    with pkgs;
    lib.lists.flatten [
      flatpak
      self.packages.${pkgs.stdenv.hostPlatform.system}.wlr-gamma-service
      keyd
      granted # access cloud
      nerdfix # fixes illegal font codepoints https://discourse.nixos.org/t/nerd-fonts-only-see-half-the-icon-set/27513
      gcsfuse # mount google cloud storage
      wkhtmltopdf # HTML to PDF

      # Desktop system packages
      libinput-gestures

      # Audio/Video/Image Utilities
      [
        pamixer
        easyeffects
        lsp-plugins  # LSP Limiter plugin for EasyEffects
        imagemagick
        vlc
        pavucontrol
        pulseaudio
        pulsemixer
        #mov-cli // errors
        mpv
        chafa
        obs-cli
        ffmpeg

        # OBS
        [
          obs-studio
          (pkgs.wrapOBS {
            plugins = with pkgs.obs-studio-plugins; [
              wlrobs
              obs-backgroundremoval
							input-overlay
            ];
          })
        ]
      ]

      # UI/UX Utilities
      [
        adwaita-qt
        bemenu
        blueman
        rust-motd
        grim
        slurp
        mako
        networkmanagerapplet
        rofi
        swappy
      ]

      # emulators
      [
        #waydroid #dbg: might be bringing in `webkitgtk`, which brings for like an hour; until resolved, comment out
        #gnome-boxes # vm with linux distros #dbg: may be bringing in `webkitgtk`, which builds stupid long
        # Windows
        [
          #DEPRECATE: a bunch of stuff here seems to be bringing the same thing in
          #wineWowPackages.stable
          #wine
          #(wine.override { wineBuild = "wine64"; })
          #wine64
					#wineWowPackages.stable
     #     wineWowPackages.staging
					wineWowPackages.waylandFull
          #wineWowPackages.wayland
          #wineWowPackages.unstableFull
          #winePackages.stagingFull
          #wine-staging # nightly wine
          winetricks # install deps for wine
          #bottles # ... python
          lutris # supposed to be more modern `playonlinux`. It's in python.
					heroic
          playonlinux # oh wait, this shit's in python too
        ]
        # MacOS
        [
          #darling
          #dmg2img
        ]
      ]

      # Coding
      [
        vscode-extensions.github.copilot
        sass # css3 tools
        mold # probably shouldn't be here though
        sccache
        just
        trunk # fascilitates running CSR web apps
        toml-cli
        bash-language-server
        tailwindcss-language-server
        jdk # java dev kit (pray for my sanity)
        htmx-lsp
        watchexec # like cargo-watch, but general and mantained

        # editors
        [
          neovim
          vscode
        ]

        # language-specific
        [
          vscode-langservers-extracted # contains json lsp
          marksman # md lsp
          perl

          # Ocaml
          [
            ocaml
            ocamlPackages.ocaml-lsp
            ocamlPackages.findlib
            ocamlformat_0_22_4
            dune_3 # build system
            opam # package manager for ocaml
            opam-publish
          ]
          # Lean
          [
            #lean4 # want to use elan instead
            leanblueprint
            elan # rustup for lean. May or may not be outdated.
          ]
          # Js / Ts
          [
            nodejs_22
            deno
          ]

          # typst
          [
            typst
            tinymist # lsp; also comes with `typlite`, - typst to latex converter
            typstyle # formatter (also formats codeblocks)
          ]
          # nix
          [
            nil # nix lsp
            niv # nix build dep management
            nix-diff
            statix # Lints and suggestions for the nix programming language
            deadnix # Find and remove unused code in .nix source files

            # formatters
            [
              nixfmt-rfc-style
              nixpkgs-fmt
              alejandra # Nix Code Formatter; not sure how it compares with nixpkgs-fmt
            ]
          ]
					# csharp
					[
						#dotnetCorePackages.sdk_10_0-bin #TODO: figure out how to get it without getting segmentation fault
						#roslyn-ls
						#roslyn
					]
          # python
          [
						python314
            ty # typechecker in rust
            python313Packages.jedi-language-server
            ruff
          ]
					# latex
					[
						texliveFull
						texlivePackages.chktex
						# miktex # builds from source, takes forever
					]
          # golang
          [
            air # live reload
            go
            gopls
          ]
          # C#
          [
            #vscode-extensions.ms-dotnettools.csharp # breaking
          ]
          # rust
          [
            # cargo, rustcs, etc are brought in by fenix.nix
            rustup
            leptosfmt # fork of rustfmt with support for formatting some leptos-specific macros

            # cargo plugins
            [
              cargo-edit # cargo add command
              cargo-expand # expand macros
              cargo-bloat # see size-sorted composition of the binary
              cargo-generate #DEPRECATE: a thing to set up a new cargo project; but I'm pretty sure my templates are just superior
              cargo-hack # wrapper around cargo, for more precise control of {features, deps, versions}, to run a command on
              cargo-udeps #DEPRECATE: unused deps; but I'm using cargo-machete atm
              cargo-outdated # display when dependencies are out of date. Q: seemes useless, as I'm just using crates.nvim for this
              cargo-rr # wrapper around rr debugger. Q: should it ever be used over gdb?
              cargo-tarpaulin # code coverage. Q: is it ever useful?
              cargo-sort # format Cargo.toml
              cargo-insta # snapshot tests
              cargo-mutants # fuzzy finding
              cargo-update # `cargo add` command
              cargo-binstall # doesn't really work on nixos #? but could it work with fhs-compat layer?
              cargo-machete # detect unused
              cargo-release # automate release (has annoying req of having to commit _before_ this runs instead of my preffered way of pushing on success of release
              cargo-watch # auto-rerun `build` or `run` command on changes #XXX: archived
              cargo-nextest # better tests
              cargo-limit # brings `lrun` and other `l$command` aliases for cargo, that suppress warnings if any errors are present.
              cargo-unused-features # detect unused feature flags
            ]
          ]

          # C/C++
          [
            clang
            libgcc
            gccgo14
            clang-tools
            cmake
            gnumake
            meson
            ninja
          ]

          # lua
          [
            lua
            lua-language-server
          ]

          # Yaml
          [
            yamlfmt
            yamllint
          ]
        ]

        # Debuggers
        [
          lldb
          gdb
          pkgs.llvmPackages.bintools
          vscode-extensions.vadimcn.vscode-lldb
        ]
      ]
    ];
}
