{
  self,
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
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
  };
  home.sessionPath = [
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

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    x11 = {
      enable = true;
      defaultCursor = "Adwaita";
    };
  };

  # Things that never need to be available with sudo
  home.packages =
    with pkgs;
    lib.lists.flatten [
      # INFO: arrays are always automatically merged, in host-specfic `home.nix`s it may seem like I'm overwriting this, but it only looks this way.
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
        discord # for when vesktop breaks, otherwise vesktop is a superset
        zulip
      ]
      [
        # Terminal apps/scripts (actually useful)
        typioca # tui monkeytype
        smassh # tui monkeytype
        neofetch
        figlet
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
}
