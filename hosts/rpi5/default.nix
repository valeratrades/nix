{ config, pkgs, lib, nixos-raspberrypi, inputs, user, ... }:
#############################################################
#
# Raspberry Pi 5. Self-contained aarch64 host, built via
# `nixos-raspberrypi.lib.nixosSystem` (brings its own nixpkgs +
# vendor kernel/firmware), deliberately NOT wired through the
# x86_64/desktop machinery in outputs/default.nix.
#
#############################################################
{
  imports = (with nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    raspberry-pi-5.page-size-16k
    raspberry-pi-5.display-vc4
    raspberry-pi-5.bluetooth
    sd-image # provides config.system.build.sdImage
  ]) ++ [
    inputs.server_upkeep.nixosModules.server_upkeep
  ];

  networking.hostName = "rpi5";
  # Plain wpa_supplicant (NOT NetworkManager): the working wifi config needs two
  # wpa_supplicant globals NM cannot set, both empirically required for this
  # Livebox + Broadcom chip combo:
  #   country=FR : the chip's regulatory firmware is self-managed and ignores the
  #                kernel regdomain; only wpa_supplicant's own country hint sticks,
  #                and it's what unlocks the AP's 5 GHz channel.
  #   sae_pwe=2  : the AP mandates WPA3-SAE hash-to-element; the default
  #                hunting-and-pecking is rejected at association (status 16).
  # PSK never enters the repo/store: the whole network block (with the inline
  # passphrase) lives in a device-only file, included at runtime. The
  # ext_password backend can't be used here — SAE hash-to-element (sae_pwe=2)
  # must precompute the password token, which needs the passphrase inline.
  hardware.wirelessRegulatoryDatabase = true;
  networking.wireless = {
    enable = true;
    extraConfig = ''
      country=FR
      sae_pwe=2
    '';
    # Provision /var/lib/wifi-network.conf (0600 root) on the device with:
    #   network={
    #     ssid="Livebox-2890"
    #     key_mgmt=SAE
    #     sae_password="<passphrase>"
    #     ieee80211w=2
    #   }
    extraConfigFiles = [ "/var/lib/wifi-network.conf" ];
  };

  # DHCP on ethernet + wifi via networkd (ethernet auto-preferred when both up).
  networking.useDHCP = false;
  systemd.network.enable = true;
  systemd.network.networks = {
    "10-end0" = { matchConfig.Name = "end0"; networkConfig.DHCP = "yes"; };
    "20-wlan0" = { matchConfig.Name = "wlan0"; networkConfig.DHCP = "yes"; };
  };

  programs.fish.enable = true; # registers fish in /etc/shells + vendor completions

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = user.sshAuthorizedKeys;
    initialPassword = "nixos"; # console fallback; change after first boot
  };
  users.users.root.openssh.authorizedKeys.keys = user.sshAuthorizedKeys;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
    # Team members ssh in as `admin` and authenticate git with their OWN key via
    # a forwarded agent (`ssh -A` / `ForwardAgent yes`). No git identity or key is
    # baked into the box — see hosts/rpi5/home.nix git block. Default is already
    # on; explicit so it's not silently turned off later.
    settings.AllowAgentForwarding = "yes";
  };

  # server watcher: disk + state-dir thresholds -> telegram. Proper system unit
  # (from the server_upkeep flake), secrets injected out-of-band (see below).
  services.server_upkeep = {
    enable = true;
    maxSize = "50GB";
    # Provisioned onto the running box, never in the repo/store. Same pattern as
    # the wifi secret. Format (0600):
    #   SERVER_UPKEEP__TELEGRAM__BOT_TOKEN=...
    #   SERVER_UPKEEP__TELEGRAM__ALERTS_CHAT=...
    # Use hosts/rpi5/provision-server-upkeep.sh to push it from sops.
    environmentFile = "/var/lib/server_upkeep.env";
  };

  # github pre-trusted so `git clone`/`pl` over SSH don't prompt on first contact.
  programs.ssh.knownHosts.github = {
    hostNames = [ "github.com" ];
    publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };

  # mDNS: advertise rpi5.local on the LAN so `ssh admin@rpi5.local` resolves.
  services.avahi = {
    enable = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  environment.systemPackages = with pkgs; [ vim git git-lfs ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  # daily GC + store optimise — the recipe's nix-gc.timer, declarative.
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 14d";
  };

  # Rust/Nix builds OOM a small box without swap (recipe made a swapfile); zram is
  # the zero-config nixos equivalent. ponytail: zram over a disk swapfile, fine for a Pi.
  zramSwap.enable = true;
  boot.tmp.cleanOnBoot = true;

  system.stateVersion = "25.11"; # matches nixos-raspberrypi's nixpkgs; changing requires migration

  system.nixos.tags =
    let cfg = config.boot.loader.raspberry-pi;
    in [ "raspberry-pi-${cfg.variant}" cfg.bootloader config.boot.kernelPackages.kernel.version ];
}
