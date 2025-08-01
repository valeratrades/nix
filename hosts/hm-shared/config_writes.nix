# this is the way I have configs written for the forking hosts (more reproducible than what I have myself).
# this is likely to contain configs for some things that are not actually shared, but text bloat is fine.
{ self, pkgs, user }: {
  home.file = {
    ".config/nvim" = {
      source = "${self}/home/config/nvim";
      recursive = true;
    };
    ".config/eww" = {
      source = "${self}/home/config/eww";
      recursive = true;
    };
    ".config/zathura" = {
      source = "${self}/home/config/zathura";
      recursive = true;
    };
    ".config/keyd" = {
      source = "${self}/home/config/keyd";
      recursive = true;
    };
    ".config/mako" = {
      source = "${self}/home/config/mako";
      recursive = true;
    };

  	".config/sway/config" = 
    (if user.kbd == "ansi" then {
      source = let
        config = builtins.readFile "${self}/home/config/sway/config";
        toReplace = builtins.trace
    "DEBUG: rewriting sway to assume `ansi` kbd for ${user.userFullName}"''xkb_variant "iso,"'';
      in if builtins.match ".*${toReplace}.*" config == null then
        throw "pattern '${toReplace}' not found in sway config"
      else
        let
          ansi =
            builtins.replaceStrings [ toReplace ] [ ''xkb_variant "ansi,"'' ]
            config;
        in pkgs.writeText "sway_conf_for_ansi_kbd"
        ansi; # TODO: also add the scripts (normally would be done with `recursive = true`)
      #builtins.trace "DEBUG: overwriting sway config with timur's" "${self}/home/config/sway/config_timur"; #TODO!!!!: gen timur's config procedurally by just `sed`ing xkb_variant line
    } else {
      source = "${self}/home/config/sway";
      recursive = true;
    });

    # ind files
    ".config/auto_redshift.toml".source =
      "${self}/home/config/auto_redshift.toml";
    ".config/todo.toml".text = ''
      github_token = { env = "GITHUB_KEY" }
      date_format = "%Y-%m-%d"

      [todos]
      path = "~/s/g/todos/"
      n_tasks_to_show = 3

      [timer]
      hard_stop_coeff = 1.5

      [activity_monitor]
      delimitor = " - "
    ''; # my own config relies on some env vars, this is a trimmed-down version
    ".config/discretionary_engine.toml".source =
      "${self}/home/config/discretionary_engine.toml";
    ".config/btc_line.toml".source = "${self}/home/config/btc_line.toml";
  };
}
