{ config, pkgs, lib, user, mylib, inputs, ... }:

{
  programs = {
    fish.enable = true;
    ssh = {
      startAgent = true;
      enableAskPassword = true;
      extraConfig = ''
        PasswordAuthentication = yes
      '';
    };
    rust-motd.enableMotdInSSHD = true;
    mtr.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = false;
    };
    nh = {
      enable = true;
      clean = {
        enable = true;
        dates = "weekly";
        extraArgs = "--keep-since 7d";
      };
    };
    git = {
      enable = true;
      lfs.enable = true;
      config = {
        user = {
          name = user.userFullName;
          email = user.masterUserEmail;
          token = "$GITHUB_KEY";
        };
        credential.helper = "store";
        core.attributesfile = "~/.gitattributes";
        pull = { rebase = true; };
        safe = { directory = "*"; };
        help = { autocorrect = 5; };
        pager = { difftool = true; };
        filter = {
          "lfs" = {
            clean = "git-lfs clean -- %f";
            smudge = "git-lfs smudge -- %f";
            process = "git-lfs filter-process";
            #required = true; # will panic on shell startup if not attached correctly
          };
        };
        fetch = { prune = true; };
        diff = {
          colorMoved = "zebra";
          colormovedws = "allow-indentation-change";
          external = "difft --color auto --background light --display side-by-side";
        };
        advice = {
          detachedHead = true;
          addIgnoredFile = false;
        };
        alias = let
          diff_ignore = ":!package-lock.json :!yarn.lock :!Cargo.lock :!flake.lock";
        in {
          m = "merge";
          r = "rebase";
          d = "--no-pager diff -- ${diff_ignore}";
          ds = "diff --staged -- ${diff_ignore}";
          s = "diff --stat -- ${diff_ignore}";
          sm = "diff --stat master -- ${diff_ignore}";
          l = "branch --list";
          unstage = "reset HEAD --";
          last = "log -1 HEAD";
          a = "add .";
          aa = "add -A";
          au = "remote add upstream";
          ao = "remote add origin";
          su = "remote set-url upstream";
          so = "remote set-url origin";
          b = "branch";
          c = "checkout";
          cb = "checkout -b";
          f = "push --force-with-lease";
          p = "pull --rebase";
          blame = "blame -w -C -C -C";
          fp = "merge-base --fork-point HEAD";
          ca = "commit -am";
          ri = "rebase --autosquash -i master";
          ra = "rebase --abort";
          rc = "rebase --continue";
          log = "-c diff.external=difft log -p --ext-diff";
          stash = "stash --all";
          hardupdate = ''!git fetch && git reset --hard "origin/$(git rev-parse --abbrev-ref HEAD)"'';
          noedit = "commit -a --amend --no-edit";
          pl = "!git pull && git lfs pull";
        };
        url."git@gist.github.com:" = { pushInsteadOf = "https://gist.github.com/"; };
        url."git@gitlab.com:" = { pushInsteadOf = "https://gitlab.com/"; };
        init = { defaultBranch = "master"; };
        push = {
          autoSetupRemote = true;
          default = "current";
        };
        rerere = {
          autoUpdate = true;
          enabled = true;
        };
        branch = {
          sort = "-committerdate";
          autoSetupMerge = "simple";
        };
        rebase = { autosquash = true; };
        merge = { conflictStyle = "zdiff3"; };
      };
    };
  };
}
