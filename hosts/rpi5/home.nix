{ pkgs, lib, self, user, ... }:
#############################################################
#
# admin's home on the rpi5 server. Deliberately lean (no
# desktop/sway/eww machinery): just the shell + editor + CLI
# niceties the `manual/fresh_server` recipe installs by hand,
# expressed declaratively and reusing the exact same config
# files the laptops use (sourced straight out of the flake).
#
#############################################################
{
  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    evil-helix
    (tmux.override { withSystemd = false; }) # see home/config tmux note: scopes fail under systemd
    git-lfs
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
    lesspipe # `lesspipe.sh`, makes `less` peek into archives/binaries

    # the fish config's prompt + history want these at init (zoxide/atuin/starship
    # are sourced unconditionally in __main__.fish); install so the shell matches
    # the laptops instead of erroring at every login.
    starship
    atuin
    zoxide
    direnv
  ];

  # Same fish setup as the laptops: a thin shellInit that sources the shared
  # __main__.fish out of the flake. Everything it pulls in resolves relative to
  # `${self}` (the whole repo lives in the store), so the server gets the same
  # aliases/functions/prompt with no copies to keep in sync.
  programs.fish = {
    enable = true;
    shellInit = ''
      set -g fish_greeting
      source ${self}/home/config/fish/__main__.fish
    '';
  };

  # nix-direnv: faster `.envrc` for the rust/nix projects cloned on-box.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    silent = true;
  };

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
