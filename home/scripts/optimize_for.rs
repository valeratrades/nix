#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::{Parser, ValueEnum};
use std::fs;
use std::path::Path;

const PLATFORM_PROFILE: &str = "/sys/firmware/acpi/platform_profile";
const PLATFORM_PROFILE_CHOICES: &str = "/sys/firmware/acpi/platform_profile_choices";
const CPU_BOOST: &str = "/sys/devices/system/cpu/cpufreq/boost";

#[derive(Debug, Clone, Copy, ValueEnum)]
enum Mode {
	/// Disable CPU boost + fans to max (cool & preserve hardware)
	Longevity,
	/// Disable CPU boost + fans to balanced (silent operation)
	Quiet,
	/// Enable CPU boost + fans to max (full power)
	Performance,
	/// Show current status
	Status,
}

#[derive(Parser)]
#[command(name = "optimize_for")]
#[command(about = "Optimize system for longevity, quiet operation, or performance")]
struct Args {
	mode: Mode,
}

fn main() {
	let args = Args::parse();

	match args.mode {
		Mode::Longevity => {
			set_boost(false);
			set_fan_profile("performance");
			println!("longevity: boost off, fans max");
		}
		Mode::Quiet => {
			set_boost(false);
			set_fan_profile("balanced");
			println!("quiet: boost off, fans balanced");
		}
		Mode::Performance => {
			set_boost(true);
			set_fan_profile("performance");
			println!("performance: boost on, fans max");
		}
		Mode::Status => {
			show_status();
		}
	}
}

fn set_boost(enabled: bool) {
	let value = if enabled { "1" } else { "0" };
	if let Err(e) = fs::write(CPU_BOOST, value) {
		eprintln!("Failed to set CPU boost: {}", e);
		std::process::exit(1);
	}
}

fn set_fan_profile(profile: &str) {
	if !Path::new(PLATFORM_PROFILE).exists() {
		eprintln!("Error: platform_profile not available");
		eprintln!("Ensure legion_laptop module is loaded with force=1");
		std::process::exit(1);
	}

	if let Err(e) = fs::write(PLATFORM_PROFILE, profile) {
		eprintln!("Failed to set fan profile: {}", e);
		std::process::exit(1);
	}
}

fn show_status() {
	let boost = fs::read_to_string(CPU_BOOST)
		.map(|s| if s.trim() == "1" { "on" } else { "off" })
		.unwrap_or("unknown");

	let fan_profile = fs::read_to_string(PLATFORM_PROFILE)
		.map(|s| s.trim().to_string())
		.unwrap_or_else(|_| "unknown".to_string());

	let choices = fs::read_to_string(PLATFORM_PROFILE_CHOICES)
		.map(|s| s.trim().to_string())
		.unwrap_or_else(|_| "".to_string());

	println!("boost: {}", boost);
	println!("fans: {}", fan_profile);
	if !choices.is_empty() {
		println!("fan profiles: {}", choices);
	}
}
