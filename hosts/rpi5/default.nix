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
  # The box is reachable over ethernet OR wifi — usually only one is plugged in.
  # Without this, networkd-wait-online blocks on the down interface until timeout,
  # stalling network-online.target (hence multi-user.target + every networked
  # unit) on every boot/switch. "Online" the moment any interface is up.
  systemd.network.wait-online.anyInterface = true;

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.bashInteractive; # lean standard server shell (not the fish laptop setup)
    openssh.authorizedKeys.keys = user.sshAuthorizedKeys;
    initialPassword = "nixos"; # console fallback; change after first boot
  };
  # `/bin/sh` = dash, matching the fresh_server recipe: POSIX scripts run identically,
  # interactive login stays bash (where direnv/atuin/starship can hook in).
  environment.binsh = "${pkgs.dash}/bin/dash";
  environment.shells = [ pkgs.bashInteractive pkgs.dash ];
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

  # Public site via a Cloudflare remote-managed tunnel. nginx serves on
  # loopback only (NEVER exposed to LAN/internet — the firewall keeps :80 shut);
  # cloudflared dials Cloudflare outbound and proxies your domain back to it, so
  # no static IP, no port-forward, no CGNAT problem. All ingress/DNS lives in the
  # Cloudflare dashboard; the box only needs the tunnel token.
  # Path-routes the evinvest stack behind one hostname, as the VPS's Caddy did:
  #   /api/v1/, /api-docs/  -> backend  :58844
  #   /mfe/, /api/embed/    -> rea      :59079  (microfrontend + its embed API)
  #   everything else       -> frontend :58843  (Next.js)
  # Loopback-only; cloudflared dials out and fronts TLS.
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts."_" = {
      default = true;
      listenAddresses = [ "127.0.0.1" "[::1]" ];
      locations = {
        "/api/v1/".proxyPass = "http://127.0.0.1:58844";
        "/api-docs/".proxyPass = "http://127.0.0.1:58844";
        "/api/embed/".proxyPass = "http://127.0.0.1:59079";
        "/mfe/".proxyPass = "http://127.0.0.1:59079";
        "/".proxyPass = "http://127.0.0.1:58843";
      };
    };
  };

  # Token-based tunnel (`cloudflared tunnel run`, token via TUNNEL_TOKEN). Secret
  # lives only in /var/lib/cloudflared.env (never in repo/store) — same pattern as
  # wifi + server_upkeep. ConditionPathExists keeps the unit inactive until the
  # token is provisioned; provision-cloudflared.sh pushes it from sops.
  systemd.services.cloudflared-tunnel = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "/var/lib/cloudflared.env";
    serviceConfig = {
      EnvironmentFile = "/var/lib/cloudflared.env";
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate --loglevel info run";
      Restart = "on-failure";
      RestartSec = "5s";
      DynamicUser = true;
    };
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

  # Tailscale: a stable name (rpi5.<tailnet>.ts.net) reachable from anywhere, so
  # off-LAN people ssh in with plain `ssh admin@rpi5.<tailnet>.ts.net` once they're
  # on the tailnet. mDNS rpi5.local stays LAN-only. Authenticate the box ONCE after
  # deploy: `sudo tailscale up` prints a login URL (no auth key baked into the repo).
  services.tailscale.enable = true;

  # The evinvest stack runs as native aarch64 here — images are built ON this box
  # (`nix run .#buildImage` for rea, `nix build .#backend-image` for the API), no
  # x86 emulation. Containers (rea :59079, backend :58844) on the host network;
  # the Next.js frontend (:58843) runs as a plain node service; nginx path-routes
  # all three behind the one cloudflare tunnel, replacing the VPS's Caddy.
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers = {
    evinvest-rea = {
      image = "localhost/rea:latest";
      extraOptions = [ "--network=host" ];
      volumes = [ "/opt/evinvest/rea-data:/data" ];
      cmd = [ "--config" "/data/config.toml" ];
    };
    evinvest-backend = {
      image = "localhost/evinvest-backend:latest";
      extraOptions = [ "--network=host" ];
      environment = {
        DATABASE_URL = "postgres://evinvest@127.0.0.1:5432/evinvest";
        BIND_ADDR = "0.0.0.0:58844";
        APP_ENV = "production";
        RUST_LOG = "info";
      };
    };
  };

  # Next.js standalone marketing site (built to /opt/evinvest/app on the box).
  systemd.services.evinvest-frontend = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    unitConfig.ConditionPathExists = "/opt/evinvest/app/server.js";
    environment = { PORT = "58843"; HOSTNAME = "127.0.0.1"; NODE_ENV = "production"; };
    serviceConfig = {
      ExecStart = "${pkgs.nodejs}/bin/node /opt/evinvest/app/server.js";
      WorkingDirectory = "/opt/evinvest/app";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # landing's backend needs Postgres (DATABASE_URL); rea uses its own SQLite.
  services.postgresql = {
    enable = true;
    ensureDatabases = [ "evinvest" ];
    ensureUsers = [{ name = "evinvest"; ensureDBOwnership = true; }];
    # local-only box: trust loopback so the host-network backend container connects
    # without a password. mkBefore = matched ahead of the default password rules.
    authentication = lib.mkBefore ''
      host all all 127.0.0.1/32 trust
      host all all ::1/128 trust
    '';
  };

  environment.systemPackages = with pkgs; [ vim git git-lfs cloudflared ];

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
