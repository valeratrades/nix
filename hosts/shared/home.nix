{
  self,
  config,
  lib,
  pkgs,
  user,
  inputs,
  ...
}:
{
  imports = [
    (
      # in my own config I symlink stuff to fascilitate experimentation. In derived setups I value reproducibility much more
      if user.userFullName == "Valera" then ./config_symlinks.nix else ./config_writes.nix
    )
  ];

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
    direnv.enable = true;
    eza.enable = true;
    yazi.enable = true;
    tmux = {
      enable = true; # dbg
      keyMode = "vi";
      shortcut = "e";
      package = pkgs.tmux;
      plugins = with pkgs; [
        tmuxPlugins.resurrect # persist sessions
        tmuxPlugins.open # open files
        tmuxPlugins.copycat # enables regex
      ];
      extraConfig = "${self}/home/config/tmux/tmux.conf";
    };
    home-manager.enable = true; # let it manage itself
  };

  dconf = {
    enable = true;
    settings."org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };

  gtk = {
    enable = true;
    theme = {
      name = "Materia-dark"; # dbg: want Adwaita-dark
      package = pkgs.materia-theme;
    };
  };

  home = {
    sessionPath = [
      "${pkgs.lib.makeBinPath [ ]}"
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
      size = 24;
      x11 = {
        enable = true;
        defaultCursor = "Adwaita";
      };
    };
    keyboard = null; # otherwise it overwrites my semimak

    # Things that never need to be available with sudo
    packages =
      with pkgs;
      # INFO: arrays are always automatically merged, in host-specfic `home.nix`s it may seem like I'm overwriting this, but it only looks this way.
      lib.lists.flatten [
        [
          # funsies
          unimatrix
          #spotify
          cowsay
        ]
        [
          # messengers
          telegram-desktop
          vesktop
          #discord # for when vesktop breaks, otherwise vesktop is a superset #dbg: was breaking for Tima
          zulip
        ]
        [
          # Terminal apps/scripts (actually useful)
          typioca # tui monkeytype
          smassh # tui monkeytype
          neofetch
          figlet
          iamb # matrix client (rust)
        ]
        [
          # nix
          nix-tree # analyse nix-store
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
        rnote
        neomutt # email client
        songrec # shazam in rust. Might come with some crazy mic patches, as running it may have just fixed my laptop's built-in mic.
        fswebcam # instant webcam photo
        anyrun # wayland-native rust alternative to rofi
        zathura # read PDFs
        pdfgrep
        xournalpp # draw on PDFs
      ]
      ++ [
        inputs.auto_redshift.packages.${pkgs.system}.default # good idea for everyone
        inputs.todo.packages.${pkgs.system}.default # here, because eww depends on it, otherwise meant for my use exclusively
        inputs.tg.packages.${pkgs.system}.default # should be reasonably generic
        inputs.bbeats.packages.${pkgs.system}.default
        inputs.reasonable_envsubst.packages.${pkgs.system}.default # definitely have scripts depending on it, and they are currently part of the shared config.
        inputs.booktyping.packages.${pkgs.system}.default
      ];

    activation = {
      # # my file arch consequences
      mkdir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/tmp/
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
      "tmp/README.md".source = "${self}/home/fs/tmp/README.md";
      #

      ".config/tg.toml".source = "${self}/home/config/tg.toml";
      ".config/tg_admin.toml".source = "${self}/home/config/tg_admin.toml";
      ".config/auto_redshift.toml".source = "${self}/home/config/auto_redshift.toml";
      ".config/todo.toml".source = "${self}/home/config/todo.toml";
      ".config/discretionary_engine.toml".source = "${self}/home/config/discretionary_engine.toml";
      ".config/btc_line.toml".source = "${self}/home/config/btc_line.toml";

      ".lesskey".source = "${self}/home/config/lesskey";
      ".config/fish/conf.d/sway.fish".source = "${self}/home/config/fish/conf.d/sway.fish";
      ".config/greenclip.toml".source = "${self}/home/config/greenclip.toml";

      ".config/iamb/config.toml".text = ''
        [profiles."master"]
        user_id =  "@valeratrades:matrix.org"
        #url = "https://matrix.org"
      '';

      # # Might be able to join these, syntaxis should be similar
      ".config/vesktop" = {
        source = "${self}/home/config/vesktop";
        recursive = true;
      };
      ".config/discord" = {
        source = "${self}/home/config/discord";
        recursive = true;
      };
      # configured via hm, can't just symlink it in my host's config
      ".config/tmux" = {
        source = "${self}/home/config/tmux";
        recursive = true;
      };
      ".cargo" = {
        source = "${self}/home/config/cargo";
        recursive = true;
      };
    };
  };
}
