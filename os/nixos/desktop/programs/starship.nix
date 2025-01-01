{
  ...
}:
{
  programs.starship = {
    enable = true; # enabled from mod.fish, using --print-full-init to fix `psub` issue. However the `enable` here is also necessary, to have right-prompt working correctly. TODO: submit a pr to enable such option in the nix starship module.
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
        format = "[$version]($style) ";
        #version_format = "$major.$minor(-$toolchain)"; # $toolchain is not recognized correctly right now (2024/10/31)
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
      right_format = "$custom$all"; # `all` does _not_ duplicate explicitly enabled modules

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

        # we'll get indication from `$signal_name` anyways, this seems like clutter. //DEPRECATED in a month (2024/10/30)
        sigint_symbol = ""; # "[🧱](bright-red)";
        signal_symbol = ""; # [⚡](bold flamingo)";

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
        #shell = ["fish" "-c"]; # must be `fish`, but I didn't figure out how to enforce it yet
        path = {
          command = ''printf (prompt_pwd)'';
          when = ''true'';
          style = "bold cyan";
          shell = "fish";
        };
        readonly = {
          command = ''printf "🔒"'';
          when = ''! [ -w . ]'';
          style = "bold red";
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
