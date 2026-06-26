{ pkgs, lib, self, user, ... }:
#############################################################
#
# admin's home on the rpi5 server. Deliberately lean (no
# desktop/sway/eww machinery): just the shell + editor + CLI
# niceties the `manual/fresh_server` recipe installs by hand,
# expressed declaratively and reusing the same config files
# the laptops use.
#
#############################################################
{
  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    evil-helix
    (tmux.override { withSystemd = false; }) # see home/config tmux note: scopes fail under systemd
    ripgrep
    fd
    bat
    eza
    dust
    htop
    ncdu
    fzf
    jq
    tree
    net-tools # `netstat`, used by the .bashrc `ports`/`myip` aliases
  ];
}
