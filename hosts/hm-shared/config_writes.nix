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
    ".config/easyeffects/output" = {
      source = "${self}/home/config/easyeffects/output";
      recursive = true;
    };
    ".config/pipewire/pipewire.conf.d" = {
      source = "${self}/home/config/pipewire/pipewire.conf.d";
      recursive = true;
    };

    # ind files
    ".config/auto_redshift.toml".source =
      "${self}/home/config/auto_redshift.toml";
    ".config/todo.toml".text = ''
      [manual_stats]
      date_format = "%Y-%m-%d"

      [milestones]
      github_token = { env = "GITHUB_KEY" }

      [todos]
      path = "~/s/g/todos/"
      n_tasks_to_show = 3

      [timer]
      hard_stop_coeff = 1.5
    '';
    ".gitattributes".text = ''
      *.jpg filter=lfs diff=lfs merge=lfs -text
      *.jpeg filter=lfs diff=lfs merge=lfs -text
      *.png filter=lfs diff=lfs merge=lfs -text
      *.gif filter=lfs diff=lfs merge=lfs -text
      *.bmp filter=lfs diff=lfs merge=lfs -text
      *.tiff filter=lfs diff=lfs merge=lfs -text
      *.webp filter=lfs diff=lfs merge=lfs -text
      *.svg filter=lfs diff=lfs merge=lfs -text
      *.pdf filter=lfs diff=lfs merge=lfs -text
    '';
	}
		// pkgs.lib.optionalAttrs (user.kbd != "ansi") (
			let
				cfgPath  = "${self}/home/config/sway/config";
				config   = builtins.readFile cfgPath;
				needle   = ''xkb_variant "iso,"'';
				replaced =
					if builtins.match ".*xkb_variant \"ansi,\".*" config != null
						then builtins.replaceStrings [ needle ] [ ''xkb_variant "iso,"'' ] config
					else throw "pattern '${needle}' not found in ${cfgPath}";
			in {
				".config/sway/config".source = pkgs.writeText "sway_conf_for_iso_kbd" replaced;
			}
		)
		// pkgs.lib.optionalAttrs (user.kbd == "ansi") {
			".config/sway" = { source = "${self}/home/config/sway"; recursive = true; };
		};
}
