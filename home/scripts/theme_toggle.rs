#!/usr/bin/env -S cargo +nightly -Zscript -q

use std::{env, fs, process::Command};

enum ThemeMode {
	Light,
	Dark,
}

struct Config {
	mode: ThemeMode,
	change_wallpaper: bool,
	light_theme_alacritty: String,
	dark_theme_alacritty: String,
	light_wallpaper: String,
	dark_wallpaper: String,
}

fn print_usage() {
	println!("Usage: theme-switcher [light|dark] [-w|--wallpaper]");
	println!("\nArguments:");
	println!("  light|dark          Required: Set the theme to light or dark mode");
	println!("  -w, --wallpaper     Optional: Also change the wallpaper");
	println!("\nExample:");
	println!("  theme-switcher dark -w    # Switch to dark theme with wallpaper");
}

fn parse_args() -> Result<Config, String> {
	let args: Vec<String> = env::args().skip(1).collect();

	if args.is_empty() {
		return Err("No arguments provided. You must specify 'light' or 'dark'.".to_string());
	}

	let mut mode = None;
	let mut change_wallpaper = false;

	for arg in &args {
		match arg.as_str() {
			"light" => mode = Some(ThemeMode::Light),
			"dark" => mode = Some(ThemeMode::Dark),
			"-w" | "--wallpaper" => change_wallpaper = true,
			"-h" | "--help" | "help" => {
				print_usage();
				std::process::exit(0);
			}
			_ => return Err(format!("Unknown argument: {}", arg)),
		}
	}

	let mode = mode.ok_or_else(|| "You must specify either 'light' or 'dark' as the theme.".to_string())?;

	Ok(Config {
		mode,
		change_wallpaper,
		light_theme_alacritty: "github_light_high_contrast".to_string(),
		dark_theme_alacritty: "github_dark".to_string(),
		light_wallpaper: "~/Wallpapers/AndreySakharov.jpg".to_string(),
		dark_wallpaper: "~/Wallpapers/girl_with_a_perl_earring.jpg".to_string(),
	})
}

fn set_theme(config: &Config) -> Result<(), String> {
	// Set GNOME theme
	let theme_value = match config.mode {
		ThemeMode::Light => "'prefer-light'",
		ThemeMode::Dark => "'prefer-dark'",
	};

	Command::new("gsettings")
		.args(["set", "org.gnome.desktop.interface", "color-scheme", theme_value])
		.status()
		.map_err(|e| format!("Failed to set gsettings: {}", e))?;

	// Notify the user
	let mode_str = match config.mode {
		ThemeMode::Light => "light",
		ThemeMode::Dark => "dark",
	};

	Command::new("notify-send")
		.args([&format!("Setting {} theme", mode_str)])
		.status()
		.map_err(|e| format!("Failed to send notification: {}", e))?;

	// Update Alacritty config
	let alacritty_config_path = env::var("HOME").map_err(|_| "Failed to get HOME environment variable".to_string())? + "/.config/alacritty/alacritty.toml";

	let config_content = fs::read_to_string(&alacritty_config_path).map_err(|e| format!("Failed to read Alacritty config: {}", e))?;

	let (from_theme, to_theme) = match config.mode {
		ThemeMode::Light => (&config.dark_theme_alacritty, &config.light_theme_alacritty),
		ThemeMode::Dark => (&config.light_theme_alacritty, &config.dark_theme_alacritty),
	};

	let new_content = config_content.replace(&format!("{}.toml", from_theme), &format!("{}.toml", to_theme));

	fs::write(&alacritty_config_path, new_content).map_err(|e| format!("Failed to write Alacritty config: {}", e))?;

	// Change wallpaper if flag is provided
	if config.change_wallpaper {
		let wallpaper_path = match config.mode {
			ThemeMode::Light => &config.light_wallpaper,
			ThemeMode::Dark => &config.dark_wallpaper,
		};

		// Expand ~ to home directory if present
		let expanded_path = if wallpaper_path.starts_with("~/") {
			let home = env::var("HOME").map_err(|_| "Failed to get HOME environment variable".to_string())?;
			wallpaper_path.replacen("~", &home, 1)
		} else {
			wallpaper_path.clone()
		};

		Command::new("swaymsg")
			.args(["output", "*", "bg", &expanded_path, "fill"])
			.status()
			.map_err(|e| format!("Failed to set wallpaper: {}", e))?;
	}

	// Update Neovim
	Command::new("nvim")
		.args(["--remote-send", "<C-\\><C-N>;lua setSystemTheme()<CR>"]) //NB: my nvim has switched `;` and `:`. Be careful with what exactly is sent here, - I couldn't understand why the standard `:lua` wasn't working.
		.status()
		.map_err(|e| format!("Failed to update Neovim: {}", e))?;

	Ok(())
}

fn main() {
	match parse_args() {
		Ok(config) =>
			if let Err(e) = set_theme(&config) {
				eprintln!("Error: {}", e);
				std::process::exit(1);
			},
		Err(e) => {
			eprintln!("Error: {}", e);
			print_usage();
			std::process::exit(1);
		}
	}
}
