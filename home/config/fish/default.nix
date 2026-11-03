{ self, pkgs, lib, config, user, ... }:
let
  # fish comes from the NixOS module, so HM's own fish integration (which sources this) is never active
  hmSessionVars = pkgs.runCommand "hm-session-vars.fish" { } ''
    ${pkgs.babelfish}/bin/babelfish < ${config.home-manager.users.${user.username}.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh > $out
  '';
in
{
  programs.fish = {
    enable = true;
    package = pkgs.fish;
    shellAliases = lib.mkForce { }; # each `alias` call costs ~0.4ms at startup; ls/ll/l/wui are functions in home/config/fish
    shellInit = ''
      			set -g fish_greeting # disable greeting
      			source ${hmSessionVars} # before __main__.fish, which execs sway
      			source ${self}/home/config/fish/__main__.fish
    '';
  };
}
