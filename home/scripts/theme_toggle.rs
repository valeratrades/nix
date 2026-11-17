#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::{Parser, ValueEnum};
use std::{env, fs, process::Command};

#[derive(Debug, Clone, Copy, ValueEnum)]
enum ThemeMode {
	Light,
	Dark,
}

/// Switch between light and dark themes
#[derive(Parser, Debug)]
#[command(name = "theme-switcher")]
#[command(about = "Switch between light and dark themes")]
struct Args {
	/// Theme mode (light or dark)
	mode: ThemeMode,

	/// Also change the wallpaper
	#[arg(short, long)]
	wallpaper: bool,
}

struct Config {
	mode: ThemeMode,
	change_wallpaper: bool,
	light_theme_alacritty: String,
	dark_theme_alacritty: String,
	light_wallpaper: String,
	dark_wallpaper: String,
}

impl From<Args> for Config {
	fn from(args: Args) -> Self {
		Config {
			mode: args.mode,
			change_wallpaper: args.wallpaper,
			light_theme_alacritty: "github_light_high_contrast".to_string(),
			dark_theme_alacritty: "github_dark".to_string(),
			light_wallpaper: "~/Wallpapers/AndreySakharov.jpg".to_string(),
			dark_wallpaper: "~/Wallpapers/girl_with_a_perl_earring.jpg".to_string(),
		}
	}
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
		.map_err(|e| format!("Failed to set gsettings: {e}"))?;

	// Notify the user
	let mode_str = match config.mode {
		ThemeMode::Light => "light",
		ThemeMode::Dark => "dark",
	};

	Command::new("notify-send")
		.args([&format!("Setting {mode_str} theme")])
		.status()
		.map_err(|e| format!("Failed to send notification: {e}"))?;

	// Update Alacritty config
	let alacritty_config_path = env::var("HOME").map_err(|_| "Failed to get HOME environment variable".to_string())? + "/.config/alacritty/alacritty.toml";

	let config_content = fs::read_to_string(&alacritty_config_path).map_err(|e| format!("Failed to read Alacritty config: {e}"))?;

	let (from_theme, to_theme) = match config.mode {
		ThemeMode::Light => (&config.dark_theme_alacritty, &config.light_theme_alacritty),
		ThemeMode::Dark => (&config.light_theme_alacritty, &config.dark_theme_alacritty),
	};

	let new_content = config_content.replace(&format!("{from_theme}.toml"), &format!("{to_theme}.toml"));

	fs::write(&alacritty_config_path, new_content).map_err(|e| format!("Failed to write Alacritty config: {e}"))?;

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
			.map_err(|e| format!("Failed to set wallpaper: {e}"))?;
	}

	Ok(())
}

fn main() {
	let args = Args::parse();
	let config = Config::from(args);

	if let Err(e) = set_theme(&config) {
		eprintln!("Error: {e}");
		std::process::exit(1);
	}
}
