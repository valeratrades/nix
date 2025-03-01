# taken from https://github.com/Mic92/dotfiles
{ pkgs
, lib
, config
, ...
}:
#let
#  nix-alien-pkgs =
#    import (builtins.fetchTarball "https://github.com/thiagokokada/nix-alien/tarball/master")
#      { };
#in
{

  environment.systemPackages = [
    #nix-alien-pkgs.nix-alien

    # # This is stolen from https://github.com/ryan4yin/nix-config
    # create a fhs environment by command `fhs`, so we can run non-nixos packages in nixos!
    (
      let
        base = pkgs.appimageTools.defaultFhsEnvArgs;
      in
      pkgs.buildFHSEnv (
        base
        // {
          name = "fhs";
          targetPkgs = pkgs: (base.targetPkgs pkgs) ++ [ pkgs.pkg-config ];
          profile = "export FHS=1";
          runScript = "fish"; # "bash";
          extraOutputsToInstall = [ "dev" ];
        }
      )
    )
    #
  ];
  services.envfs.enable = lib.mkDefault true;

  programs.nix-ld = {
    enable = lib.mkDefault true;
    libraries =
      with pkgs;
      [
        acl
        attr
        bzip2
        dbus
        expat
        fontconfig
        freetype
        fuse3
        icu
        libclang
        libnotify
        libsodium
        libssh
        libunwind
        libusb1
        libuuid
        nspr
        nss
        stdenv.cc.cc
        util-linux
        zlib
        zstd
      ]
      ++ lib.optionals (config.hardware.graphics.enable) [
        pipewire
        cups
        libxkbcommon
        pango
        mesa
        libdrm
        libglvnd
        libpulseaudio
        atk
        cairo
        alsa-lib
        at-spi2-atk
        at-spi2-core
        gdk-pixbuf
        glib
        gtk3
        libGL
        libappindicator-gtk3
        vulkan-loader
        xorg.libX11
        xorg.libXScrnSaver
        xorg.libXcomposite
        xorg.libXcursor
        xorg.libXdamage
        xorg.libXext
        xorg.libXfixes
        xorg.libXi
        xorg.libXrandr
        xorg.libXrender
        xorg.libXtst
        xorg.libxcb
        xorg.libxkbfile
        xorg.libxshmfence
      ];
  };
}
