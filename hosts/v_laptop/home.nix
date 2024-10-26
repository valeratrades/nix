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

	#sops = {
		#defaultSopsFile = /home/v/s/g/private/sops.json;
		#defaultSopsFormat = "json";
		#defaultSopsFile = /home/v/s/g/private/sops.yaml;
		#secrets."github".sopsFile = /home/v/s/g/private/sops.yaml;
	#};


	imports = [
		../../home/config/fish/default.nix
	];


	home.file = {
		#".config/nix/nix.conf".text = ''
		#	access-tokens = github.com=${config.sops.secrets.github_token}
		#'';

		#"${self}/home/config/tg.toml".source = ./config/tg.toml;
		#"${self}/home/config/tg_admin.toml".source = ./config/tg_admin.toml;
		#"${self}/home/config/todo".source = ./config/todo.toml;
		#"${self}/home/config/discretionary_engine.toml".source = ./config/discretionary_engine.toml;
		#"${self}/home/config/btc_line.toml".source = ./config/btc_line.toml;
		#
		#"${self}/home/config/greenclip.toml".source = ./config/greenclip.toml;

		"${config.home.homeDirectory}/config/tg.toml".source = ../../home/config/tg.toml;
		#"${config.home.homeDirectory}/config/tg_admin.toml".source = "${nix_home}/config/tg_admin.toml";
		#"${config.home.homeDirectory}/config/todo".source = "${nix_home}/config/todo.toml";
		#"${config.home.homeDirectory}/config/discretionary_engine.toml".source = "${nix_home}/config/discretionary_engine.toml";
		#"${config.home.homeDirectory}/config/btc_line.toml".source = "${nix_home}/config/btc_line.toml";
		#
		#"${config.home.homeDirectory}/config/greenclip.toml".source = "${nix_home}/config/greenclip.toml";
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
