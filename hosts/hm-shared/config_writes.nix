# this is the way I have configs written for the forking hosts (more reproducible than what I have myself).
# this is likely to contain configs for some things that are not actually shared, but text bloat is fine.
{ self, user }:
{
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
    ".config/alacritty" = {
      source = "${self}/home/config/alacritty";
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

    ".config/sway" = {
      source = "${self}/home/config/sway";
      recursive = true;
    };

    ".config/sway/config" =
      if user.userFullName == "Timur" then
        {
          source = builtins.trace "DEBUG: overwriting sway config with timur's" "${self}/home/config/sway/config_timur";
        }
      else
        { };

    # ind files
    ".config/tg.toml".source = "${self}/home/config/tg.toml";
    ".config/tg_admin.toml".source = "${self}/home/config/tg_admin.toml";
    ".config/auto_redshift.toml".source = "${self}/home/config/auto_redshift.toml";
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
    ".config/discretionary_engine.toml".source = "${self}/home/config/discretionary_engine.toml";
    ".config/btc_line.toml".source = "${self}/home/config/btc_line.toml";
  };
}
