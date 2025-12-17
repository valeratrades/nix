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

#[derive(Debug, Clone, Copy, ValueEnum)]
enum Profile {
	Performance,
	Balanced,
	Quiet,
	Status,
}

impl Profile {
	fn as_sysfs(&self) -> Option<&'static str> {
		match self {
			Profile::Performance => Some("performance"),
			Profile::Balanced => Some("balanced"),
			Profile::Quiet => Some("quiet"),
			Profile::Status => None,
		}
	}
}

#[derive(Parser)]
#[command(name = "fans")]
#[command(about = "Control Lenovo Legion laptop fan/thermal profile")]
struct Args {
	profile: Profile,
}

fn main() {
	let args = Args::parse();

	if !Path::new(PLATFORM_PROFILE).exists() {
		eprintln!("Error: platform_profile not available");
		eprintln!("Ensure legion_laptop module is loaded with force=1");
		eprintln!("Add to NixOS config:");
		eprintln!("  boot.extraModulePackages = [ config.boot.kernelPackages.lenovo-legion-module ];");
		eprintln!("  boot.extraModprobeConfig = \"options legion_laptop force=1\";");
		std::process::exit(1);
	}

	match args.profile.as_sysfs() {
		Some(profile) => set_profile(profile),
		None => show_status(),
	}
}

fn set_profile(profile: &str) {
	match fs::write(PLATFORM_PROFILE, profile) {
		Ok(_) => println!("{}", profile),
		Err(e) => {
			eprintln!("Failed to set profile: {}", e);
			eprintln!("Try running with sudo");
			std::process::exit(1);
		}
	}
}

fn show_status() {
	let current = fs::read_to_string(PLATFORM_PROFILE)
		.map(|s| s.trim().to_string())
		.unwrap_or_else(|_| "unknown".to_string());

	let choices = fs::read_to_string(PLATFORM_PROFILE_CHOICES)
		.map(|s| s.trim().to_string())
		.unwrap_or_else(|_| "".to_string());

	println!("{}", current);
	if !choices.is_empty() {
		println!("available: {}", choices);
	}
}
