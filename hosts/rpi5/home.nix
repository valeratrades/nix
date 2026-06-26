{ pkgs, lib, self, user, ... }:
#############################################################
#
# admin's home on the rpi5 server. It's a server, not a
# laptop: login shell is plain dash, no fish/prompt/eww
# machinery — just the editor + tmux + the CLI tools the
# `manual/fresh_server` recipe installs by hand, sharing the
# laptops' editor/tmux config files straight out of the flake.
#
#############################################################
{
  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    evil-helix
    (tmux.override { withSystemd = false; }) # see home/config tmux note: scopes fail under systemd
    git-lfs
    ripgrep
    bat
    eza
    dust
    htop
    ncdu
    fzf
    jq
    tree
    net-tools # `netstat`/`ports`
    lesspipe # makes `less` peek into archives/binaries
  ];

  # Interactive shell is bash (dash is /bin/sh — see default.nix). bash because
  # the three tools below only hook into bash/zsh/fish, never dash. HM manages
  # ~/.bashrc so their init lines get injected.
  programs.bash.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true; # faster `.envrc` for the on-box nix/rust projects
    silent = true;
  };
  programs.atuin.enable = true; # better shell history (its own DB; `atuin login` to sync)
  programs.starship.enable = true;

  # Shared, untouched: editor config + the whole tmux dir (its tmux.conf is
  # self-contained — own prefix, helper scripts alongside it, plugins disabled).
  xdg.configFile = {
    "helix/config.toml".source = "${self}/home/config/helix/config.toml";
    "helix/themes".source = "${self}/home/config/helix/themes";
    "tmux" = {
      source = "${self}/home/config/tmux";
      recursive = true;
    };
  };

  # Multi-user box: NO baked git identity. Team members ssh in as `admin` and
  # authenticate git over their OWN forwarded ssh agent (`ssh -A`), and git
  # refuses to invent a commit author rather than mislabel one. github is already
  # in knownHosts (hosts/rpi5/default.nix). `pl` = pull + lfs pull, as on desktop.
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      alias.pl = "!git pull && git lfs pull";
      user.useConfigOnly = true; # error on commit unless the committer sets their own name/email
      init.defaultBranch = "main";
      pull.rebase = true;
      safe.directory = "*";
      core.attributesfile = "${self}/home/config/gitattributes";
    };
  };
}
