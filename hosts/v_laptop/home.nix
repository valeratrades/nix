{ self, config, pkgs, inputs, ... }:

#TODO!: move much of this to shared dirs
{
	home.username = "v";
	home.homeDirectory = "/home/v";

	imports = [
		../../home/config/fish/mod.nix
	];

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
	home.packages = with pkgs; [
		cowsay
		unimatrix
		spotify
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
		#inputs.auto_redshift.packages.${pkgs.system}.auto_redshift
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
