{ config, lib, pkgs, ... }:
let
  cfg = config.programs.starship;

  # Verbatim from nixos/modules/programs/starship.nix, which keeps `settingsFile` in a `let`.
  # Needed because we drop the module's fish block below but must keep the path it exported.
  # Identical expression => identical derivation, so this costs no extra build.
  userSettingsFile = (pkgs.formats.toml { }).generate "starship.toml" cfg.settings;
  settingsFile =
    if cfg.presets == [ ] then
      userSettingsFile
    else
      pkgs.runCommand "starship.toml" { nativeBuildInputs = [ pkgs.yq ]; } ''
        tomlq -s -t 'reduce .[] as $item ({}; . * $item)' \
          ${lib.concatStringsSep " " (map (f: "${cfg.package}/share/starship/presets/${f}.toml") cfg.presets)} \
          ${userSettingsFile} \
          > $out
      '';
in
{
  # The module's fish block ends in `eval (starship init fish)`, but home/config/fish/__main__.fish
  # already inits starship with `--print-full-init` — which is what dodges the psub-under-tmux bug,
  # and is why we can't just drop ours instead. Keep only the STARSHIP_CONFIG export.
  #TODO: submit a pr adding an option to skip the shell init, so this override and the copy of
  # `settingsFile` above both go away.
  programs.fish.promptInit = lib.mkForce ''
    if not test -f "$HOME/.config/starship.toml"
      set -x STARSHIP_CONFIG ${settingsFile}
    end
  '';

  # with interactiveOnly = false the module writes shellInit instead, and the duplicate would return
  assertions = [
    {
      assertion = cfg.interactiveOnly;
      message = "os/nixos/shared/programs/starship.nix overrides programs.fish.promptInit, which the starship module only writes when interactiveOnly is set";
    }
  ];

  programs.starship = {
    enable = true; # generates the settings toml; the fish-side init lives in home/config/fish/__main__.fish
    interactiveOnly = true; # only use it when shell is interactive
    # defined here, as `hm` doesn't yet recognize the `presets` option on `starship` (2024/10/31)
    presets = [ "no-runtime-versions" ]; # noisy on python, lua, and all the languages I don't care about. Would rather explicitly setup expansions on the important ones.
    settings = {
      # "no-runtime-versions" doesn't get rid of the `via` prefix, which almost makes it useless
      lua = {
        format = "[$symbol]($style) ";
      };
      typst = {
        format = "[$symbol]($style) ";
      };
      python = {
        format = "[$symbol(\($virtualenv\))]($style) "; # didn't get virtualenv to work yet
      };
      ocaml = {
        format = "[$symbol]($style) ";
      };
      c = {
        format = "[$symbol]($style) ";
      };
      ruby = {
        format = "[$symbol]($style) ";
      };
      nodejs = {
        format = "[$symbol]($style) ";
      };
      rust = {
        disabled = true; # relies on rustup. This doesn't generalize. Updated (in `custom`) to use `rustc` from the active env instead.
        format = "[$version]($style) ";
      };
    };
    settings = {
      # tipbits:
      # - `symbol` usually has a trailing whitespace
      add_newline = false;
      aws.disabled = true;
      gcloud.disabled = true;
      line_break.disabled = true;
      palette = "google_calendar";

      format = "$username$status$character";
      right_format = "\${custom.readonly}\${custom.path}$git_branch$git_commit$git_state$git_status\${custom.rust}$all"; # `all` does _not_ duplicate explicitly enabled modules

      hostname = {
        style = "white";
        ssh_only = true;
      };
      shell = {
        disabled = false;
        format = "$indicator";
        fish_indicator = "";
        bash_indicator = "[BASH](bright-white) ";
        zsh_indicator = "[ZSH](bright-white) ";
      };
      nix_shell = {
        symbol = "";
        format = "[$symbol]($style) ";

        style = "bold blue";
        pure_msg = "";
        impure_msg = "[impure shell](yellow)";
      };
      git_branch = {
        format = "[$branch(:$remote_branch)]($style) ";
      };
      cmd_duration = {
        format = "[$duration]($style) ";
        style = "white";

        min_time = 2000; # milliseconds; min to display
        show_milliseconds = false;
        min_time_to_notify = 45000; # milliseconds
        #show_notifications = true; # produces noise on exiting `tmux`
      };
      time = {
        format = "[$time]($style)";
        disabled = false;
      };
      package = {
        disabled = true;
      };
      directory = {
        disabled = true;
        truncation_length = 0; # disables truncation
      };
      # Only useful for vim-mode, but I prefer to use my global vim keyd layer instead. Rest of this module is reimplemented with `status`.
      character = {
        disabled = true;
      };
      direnv = {
        format = "[$symbol$allowed]($style) ";
        symbol = " ";

        style = "bold basil";
        denied_msg = "-";
        not_allowed_msg = "~";
        allowed_msg = "+";

        #format = "[$symbol]($allowed) "; # starship is not smart enough. Leaving for if it gets better.
        #denied_msg = "purple";
        #not_allowed_msg = "bold red";
        #allowed_msg = "bold basil";

        disabled = false;
      };
      status = {
        # ? can I remake the `$character` with this?
        #success_symbol = "  "; # preserve indent
        format = "([$signal_name](bold flamingo) )$int $symbol"; # brackets around `signal_name` to not add whitespace when it's empty

        pipestatus = true;
        pipestatus_format = "\[$pipestatus\] => ([$signal_name](bold flamingo) )$int";

        success_symbol = "[❯ ](bold green)";
        symbol = "[❌](bold red)";
        not_executable_symbol = "[🚫](bold banana)";
        not_found_symbol = "[🔍](bold tangerine)";
        map_symbol = true;

        # we'll get indication from `$signal_name` anyways, this seems like clutter.
        sigint_symbol = "";
        signal_symbol = "";

        disabled = false;
      };
      shlvl = {
        format = "[$shlvl]($style) ";
        style = "bright-red";
        threshold = 3; # do most things from tmux, so otherwise carries no info
        disabled = false;
      };

      #TODO!: sigure out how to quickly estimate the dir size, display here with `(gray)`
      # if ordering is not forced, will be sorted alphabetically
      custom = {
        path = {
          # replicates fish's `prompt_pwd` function
          command = ''
            case "$PWD" in
              "$HOME"*) p="~''${PWD#"$HOME"}" ;;
              *) p="$PWD" ;;
            esac
            printf "%s" "$p" | sed 's:\([^/]\)[^/]*/:\1/:g'
          '';
          when = ''true'';
          style = "bold cyan";
          shell = ["dash"];
        };
        # every custom module must pin `shell`: unset falls back to $STARSHIP_SHELL (fish),
        # so each `when` would pay a full interactive fish startup (~240ms) per prompt
        readonly = {
          command = ''printf "🔒"'';
          when = ''! [ -w . ]'';
          style = "bold red";
          shell = ["dash"];
        };
        rust = {
          command = ''rustc -V | cut -d ' ' -f 2'';
          when = ''[ -f Cargo.toml ] || [ -n "$(find . -maxdepth 1 -name "*.rs" 2>/dev/null | head -1)" ]'';
          style = "bold red";
          shell = ["dash"];
        };
      };

      palettes.google_calendar = {
        lavender = "141";
        sage = "120";
        grape = "135";
        flamingo = "203";
        banana = "227";
        tangerine = "214";
        peacock = "39";
        graphite = "240";
        blueberry = "63";
        basil = "64";
        tomato = "160";
      };
    };
  };
}
