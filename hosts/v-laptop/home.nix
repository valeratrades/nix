# TODO!: move much of this to shared dirs
{ self, config, lib, pkgs, inputs, mylib, user, ... }:
let
  #TODO: `ssh-add ~/.ssh/id_ed25519` as part of the setup
  sshConfigPath = "${config.home.homeDirectory}/.ssh";
in {
  nix.extraOptions = "!include ${config.home.homeDirectory}/s/g/private/sops/";
  # ref: https://www.youtube.com/watch?v=G5f6GC7SnhU
  sops = {
    age.sshKeyPaths = [ "${sshConfigPath}/id_ed25519" ];
    defaultSopsFile = "${self}/secrets/users/v/default.json";
    defaultSopsFormat = "json";
    secrets.telegram_token_main = { mode = "0400"; };
    secrets.telegram_token_test = { mode = "0400"; };
    secrets.mail_main_addr = { mode = "0400"; };
    secrets.mail_main_pass = { mode = "0400"; };
    secrets.mail_spam_addr = { mode = "0400"; };
    secrets.mail_spam_pass = { mode = "0400"; };
  };

  tg = {
    enable = true;
    package = inputs.tg.packages.${pkgs.system}.default;
    token = config.sops.secrets.telegram_token_main.path;
  };

  home = {
    packages = with pkgs;
      builtins.trace "DEBUG: sourcing Valera-specific home.nix"
      lib.lists.flatten [
        nyxt
        chromium
        code-cursor
        en-croissant # chess analysis GUI
        ncspot
        gitui
        lazygit
        zed

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
        inputs.ask_llm.packages.${pkgs.system}.default
        inputs.translate_infrequent.packages.${pkgs.system}.default
        inputs.cargo_sort_derives.packages.${pkgs.system}.default

        #inputs.aggr_orderbook.packages.${pkgs.system}.default
        #inputs.orderbook_3d.packages.${pkgs.system}.default
      ];
    #TODO: himalaya. Problems: (gmail requires oauth2, proton requires redirecting to it (also struggling with it))
    file = {
      ".config/himalaya/config.toml".source =
        (pkgs.formats.toml { }).generate "" {
          accounts.master = {
            default = true;
            email = "valeratrades@gmail.com";
            display-name = "valeratrades";
            downloads-dir = "/home/v/Downloads";
            backend.type = "imap";
            backend.host = "imap.gmail.com";
            backend.port = 993;
            backend.login = "valeratrades@gmail.com";
            backend.encryption.type = "tls";
            backend.auth.type = "password";
            backend.auth.command =
              "cat ${config.sops.secrets.mail_main_pass.path}";
            message.send.backend.type = "smtp";
            message.send.backend.host = "smtp.gmail.com";
            message.send.backend.port = 465;
            message.send.backend.login = "valeratrades@gmail.com";
            message.send.backend.encryption.type = "tls";
            message.send.backend.auth.type = "password";
            message.send.backend.auth.command =
              "cat ${config.sops.secrets.mail_main_pass.path}";
          };
        };
      ".config/todo.toml".source = "${self}/home/config/todo.toml";
    };
  };
}
