#TODO!: move much of this to shared dirs


#{
#  self,
#  ...
#}: {
#  config,
#  pkgs,
#  lib,
#  ...
#}:

{ self, config, pkgs, inputs, ... }:
let
	nix_home = "../../home";
in {
	home.username = "v";
	home.homeDirectory = "/home/v";

	#nix.extraOptions = "include ${config.home.homeDirectory}/s/g/private/sops.conf";
	#sops = {
	#	defaultSopsFile = "${config.home.homeDirectory}/s/g/private/sops.yaml";
	#};

		#defaultSopsFile = /home/v/s/g/private/sops.json;
		#defaultSopsFormat = "json";


	imports = [
		../../home/config/fish/default.nix
	];


	home.file = {
		"${config.home.homeDirectory}/.config/tg.toml".source = ../../home/config/tg.toml;
		"${config.home.homeDirectory}/.config/tg_admin.toml".source = ../../home/config/tg_admin.toml;
		"${config.home.homeDirectory}/.config/todo.toml".source = ../../home/config/todo.toml;
		"${config.home.homeDirectory}/.config/discretionary_engine.toml".source = ../../home/config/discretionary_engine.toml;
		"${config.home.homeDirectory}/.config/btc_line.toml".source = ../../home/config/btc_line.toml;
		"${config.home.homeDirectory}/.lesskey".source = ../../home/config/lesskey;
		"${config.home.homeDirectory}/.config/fish/conf.d/sway.fish".source = ../../home/config/fish/conf.d/sway.fish;

		"${config.home.homeDirectory}/.config/greenclip.toml".source = ../../home/config/greenclip.toml;

		"${config.home.homeDirectory}/.config/nvim" = {
			source = ../../home/config/nvim;
			recursive = true;
		};
		"${config.home.homeDirectory}/.config/eww" = {
			source = ../../home/config/eww;
			recursive = true;
		};
		"${config.home.homeDirectory}/.config/zathura" = {
			source = ../../home/config/zathura;
			recursive = true;
		};
		"${config.home.homeDirectory}/.config/sway" = {
			source = ../../home/config/sway;
			recursive = true;
		};

		# # Might be able to join these, syntaxis should be similar
		"${config.home.homeDirectory}/.config/vesktop" = {
			source = ../../home/config/vesktop;
			recursive = true;
		};
		"${config.home.homeDirectory}/.config/discord" = {
			source = ../../home/config/discord;
			recursive = true;
		};
		#


		"${config.home.homeDirectory}/.config/alacritty" = {
			source = ../../home/config/alacritty;
			recursive = true;
		};
		"${config.home.homeDirectory}/.config/keyd" = {
			source = ../../home/config/keyd;
			recursive = true;
		};

		"/usr/share/X11/xkb/symbols" = {
			source = ../../home/config/xkb_symbols;
			recursive = true;
		};
	};


	# link the configuration file in current directory to the specified location in home directory
	# home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;

	# link all files in `./scripts` to `~/.config/i3/scripts`
	# home.file.".config/i3/scripts" = {
	#   source = ./scripts;
	#   recursive = true;   # link recursively
	#   executable = true;  # make all files executable
	# };

	# encode the file content in nix configuration file directly
	# home.file.".xxx".text = ''
	#     xxx
	# '';

	# Things that never need to be available with sudo
	home.packages = with pkgs; lib.flatten [
		cowsay
		unimatrix
		spotify
		spotube
		telegram-desktop
		vesktop
		rnote
		zathura
		ncspot
		neomutt
		neofetch
		figlet
		zulip
		bash-language-server # needs unstable rn (2024/10/21)

		# my packages
		[
		inputs.auto_redshift.packages.${pkgs.system}.default
		inputs.todo.packages.${pkgs.system}.default
		inputs.booktyping.packages.${pkgs.system}.default
		inputs.btc_line.packages.${pkgs.system}.default
		inputs.tg.packages.${pkgs.system}.default

		#inputs.aggr_orderbook.packages.${pkgs.system}.default
		#inputs.orderbook_3d.packages.${pkgs.system}.default
		]
	];

	#home.packages = with nixpkgs-stable: [
	#	google-chrome
	#];

	gtk = {
		enable = true;
		theme = {
			name = "Materia-dark"; #dbg: Adwaita-dark
			package = pkgs.materia-theme;
		};
	};

	dconf.settings = {
		"org/gnome/desktop/interface" = {
			color-scheme = "prefer-dark";
		};
	};

	home.pointerCursor = {
		name = "Adwaita";
		package = pkgs.adwaita-icon-theme;
		size = 24;
		x11 = {
			enable = true;
			defaultCursor = "Adwaita";
		};
	};

	home.sessionPath = [
		"${pkgs.lib.makeBinPath [ ]}"
		"${config.home.homeDirectory}/s/evdev/"
		"${config.home.homeDirectory}/.cargo/bin/"
		"${config.home.homeDirectory}/go/bin/"
		"/usr/lib/rustup/bin/"
		"${config.home.homeDirectory}/.local/bin/"
		"${config.home.homeDirectory}/pkg/packages.modular.com_mojo/bin"
		"${config.home.homeDirectory}/.local/share/flatpak"
		"/var/lib/flatpak"
	];


	programs.direnv.enable = true;

	# basic configuration of git, please change to your own
	#programs.git = {
	#  enable = true;
	#  userName = "Ryan Yin";
	#  userEmail = "xiaoyin_c@qq.com";
	#};

	# starship - an customizable prompt for any shell
	#programs.starship = {
	#  enable = true;
	#  # custom settings
	#  settings = {
	#    add_newline = false;
	#    aws.disabled = true;
	#    gcloud.disabled = true;
	#    line_break.disabled = true;
	#  };
	#};

	# alacritty - a cross-platform, GPU-accelerated terminal emulator
	#programs.alacritty = {
	#  enable = true;
	#  # custom settings
	#  settings = {
	#    env.TERM = "xterm-256color";
	#    font = {
	#      size = 12;
	#      draw_bold_text_with_bright_colors = true;
	#    };
	#    scrolling.multiplier = 5;
	#    selection.save_to_clipboard = true;
	#  };
	#};

	programs.home-manager.enable = true; # let it manage itself
	home.stateVersion = "24.05"; #NB: DO NOT CHANGE, same as `system.stateVersion`
}
