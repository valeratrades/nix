#TODO!: move much of this to shared dirs
{
  self,
  config,
  lib,
  pkgs,
  inputs,
  mylib,
  user,
  ...
}:
let
  sshConfigPath = "${config.home.homeDirectory}/.ssh";
in
{
  nix.extraOptions = "!include ${config.home.homeDirectory}/s/g/private/sops/";
  sops = {
    age.sshKeyPaths = [ "${sshConfigPath}/id_ed25519" ];
    #defaultSopsFile = "${config.home.homeDirectory}/s/g/private/sops/creds.json";
    defaultSopsFile = "${self}/secrets/users/v/default.yaml";
    #defaultSopsFormat = "json";
    validateSopsFiles = false; # required if sops file is outside of nix store
    gnupg.home = "${config.home.homeDirectory}/.gnupg";
    secrets.telegram_token_main = {
      sopsFile = "${config.home.homeDirectory}/s/g/private/sops/creds.json";
      format = "json";
    };
  };

  #NB: section names are different from what it would be inside `configuration.nix`
  systemd.user.services.tg-server = {
    Unit = {
      Description = "TG Server Service";
      After = [ "network.target" ];
    };

    Install = {
      WantedBy = [ "default.target" ];
    };

    Service = {
      Type = "simple";
      LoadCredential = "tg_token:${config.sops.secrets.telegram_token_main.path}";
      ExecStart = ''
        /bin/sh -c '${inputs.tg.packages.${pkgs.system}.default}/bin/tg --token "$(cat %d/tg_token)" server'
      '';
      Restart = "on-failure";
    };
  };

  home = {
    packages =
      with pkgs;
      builtins.trace "DEBUG: sourcing Valera-specific home.nix" lib.lists.flatten [
        nyxt
        chromium
        en-croissant # chess analysis GUI
        ncspot
        gitui

        libinput
        #flutterPackages-source.stable // errors

        virt-viewer
      ]

      ++ [
        # some of my own packages are in shared, not everything is here
        inputs.btc_line.packages.${pkgs.system}.default
        inputs.prettify_log.packages.${pkgs.system}.default
        inputs.distributions.packages.${pkgs.system}.default # ? shared?
        inputs.rm_engine.packages.${pkgs.system}.default
        inputs.bad_apple_rs.packages.${pkgs.system}.default

        #inputs.aggr_orderbook.packages.${pkgs.system}.default
        #inputs.orderbook_3d.packages.${pkgs.system}.default
      ];
  };
}
