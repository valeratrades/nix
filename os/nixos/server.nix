{ config, pkgs, lib, user, mylib, inputs, ... }:

let
  userHome = config.users.users."${user.username}".home;
in {
  imports = [
    ./shared-services.nix
    ./shared-programs.nix
  ];

  virtualisation = {
    docker = {
      enable = true;
      package = pkgs.docker;
    };
  };

  environment.systemPackages = with pkgs; [
    # Server-specific packages
    nginx
    caddy
    docker-compose
    docker-compose-language-service
    docker-client
    arion
    podman-compose
    bettercap
    wireshark
    tshark
  ];
}