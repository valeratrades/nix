#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::{Parser, Subcommand};
use std::fs;
use std::path::Path;
use std::process::Command;

// Legion laptop module path (requires lenovo-legion-module kernel module)
const LEGION_HWMON_BASE: &str = "/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00";

#[derive(Parser)]
#[command(name = "fans")]
#[command(about = "Control Lenovo Legion laptop fan mode")]
struct Args {
	#[command(subcommand)]
	command: FanCommand,
}

#[derive(Subcommand)]
enum FanCommand {
	/// Set fans to maximum speed
	Max,
	/// Set fans to automatic mode
	Auto,
	/// Show current fan mode status
	Status,
}

fn main() {
	let args = Args::parse();

	if !is_legion_module_loaded() {
		eprintln!("Error: legion_laptop kernel module not loaded");
		eprintln!("Add to NixOS config:");
		eprintln!("  boot.extraModulePackages = [ config.boot.kernelPackages.lenovo-legion-module ];");
		eprintln!("  environment.systemPackages = [ pkgs.lenovo-legion ];");
		std::process::exit(1);
	}

	match args.command {
		FanCommand::Max => set_max_fan_speed(true),
		FanCommand::Auto => set_max_fan_speed(false),
		FanCommand::Status => show_status(),
	}
}

fn is_legion_module_loaded() -> bool {
	Path::new(LEGION_HWMON_BASE).exists()
}

fn find_hwmon_dir() -> Option<String> {
	let hwmon_path = format!("{}/hwmon", LEGION_HWMON_BASE);
	if let Ok(entries) = fs::read_dir(&hwmon_path) {
		for entry in entries.flatten() {
			let name = entry.file_name();
			if name.to_string_lossy().starts_with("hwmon") {
				return Some(entry.path().to_string_lossy().to_string());
			}
		}
	}
	None
}

fn set_max_fan_speed(enable: bool) {
	let cmd = if enable {
		"maximumfanspeed-enable"
	} else {
		"maximumfanspeed-disable"
	};

	let status = Command::new("sudo")
		.args(["legion_cli", cmd])
		.status();

	match status {
		Ok(s) if s.success() => {
			if enable {
				println!("Maximum fan speed enabled");
			} else {
				println!("Automatic fan mode restored");
			}
		}
		Ok(s) => {
			eprintln!("Failed: exit code {:?}", s.code());
			std::process::exit(1);
		}
		Err(e) => {
			eprintln!("Failed to run legion_cli: {}", e);
			std::process::exit(1);
		}
	}
}

fn show_status() {
	// Check maximum fan speed status
	let output = Command::new("legion_cli")
		.arg("maximumfanspeed-status")
		.output();

	match output {
		Ok(out) => {
			let status = String::from_utf8_lossy(&out.stdout);
			let status = status.trim();
			println!("Maximum fan speed: {}", status);
		}
		Err(e) => {
			eprintln!("Error getting status: {}", e);
		}
	}

	// Show hwmon info if available
	if let Some(hwmon) = find_hwmon_dir() {
		// Try to read fan speeds
		for i in 1..=3 {
			let fan_input = format!("{}/fan{}_input", hwmon, i);
			if let Ok(rpm) = fs::read_to_string(&fan_input) {
				println!("Fan {}: {} RPM", i, rpm.trim());
			}
		}
	}
}
