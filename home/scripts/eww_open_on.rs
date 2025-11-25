#!/usr/bin/env nix
---cargo
#! nix shell --impure --expr ``
#! nix let rust_flake = builtins.getFlake ''github:oxalica/rust-overlay'';
#! nix     nixpkgs_flake = builtins.getFlake ''nixpkgs'';
#! nix     pkgs = import nixpkgs_flake {
#! nix       system = builtins.currentSystem;
#! nix       overlays = [rust_flake.overlays.default];
#! nix     };
#! nix     toolchain = pkgs.rust-bin.nightly."2025-10-10".default.override {
#! nix       extensions = ["rust-src"];
#! nix     };
#! nix
#! nix in toolchain
#! nix ``
#! nix --command sh -c ``cargo -Zscript -q "$0" "$@"``

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde_json = "1.0"
---

use clap::{Parser, Subcommand};
use std::process::Command;

/// Opens eww windows on Sway monitors
#[derive(Parser, Debug)]
#[command(name = "eww_open_on")]
#[command(about = "Opens eww windows on Sway monitors")]
struct Args {
	#[command(subcommand)]
	command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
	/// Open eww windows on the currently focused monitor
	OnFocused,
	/// Open eww windows on all active monitors
	All,
}

fn get_focused_monitor_index() -> Result<usize, String> {
	let output = Command::new("swaymsg")
		.args(["-t", "get_outputs"])
		.output()
		.map_err(|e| format!("Failed to run swaymsg: {}", e))?;

	if !output.status.success() {
		return Err("swaymsg failed".to_string());
	}

	let json_str = String::from_utf8(output.stdout).map_err(|e| format!("Invalid UTF-8: {}", e))?;

	let outputs: serde_json::Value =
		serde_json::from_str(&json_str).map_err(|e| format!("Failed to parse JSON: {}", e))?;

	let outputs_array = outputs.as_array().ok_or("Expected array of outputs")?;

	// Find focused output name
	let focused_name = outputs_array
		.iter()
		.find(|o| o["focused"].as_bool().unwrap_or(false))
		.and_then(|o| o["name"].as_str())
		.ok_or("No focused output found")?;

	// Get active outputs sorted by position
	let mut active_outputs: Vec<_> = outputs_array
		.iter()
		.filter(|o| o["active"].as_bool().unwrap_or(false))
		.collect();

	active_outputs.sort_by_key(|o| {
		let x = o["rect"]["x"].as_i64().unwrap_or(0);
		let y = o["rect"]["y"].as_i64().unwrap_or(0);
		(x, y)
	});

	// Find index of focused output
	active_outputs
		.iter()
		.position(|o| o["name"].as_str() == Some(focused_name))
		.ok_or_else(|| "Focused output not in active outputs list".to_string())
}

fn get_all_monitor_indices() -> Result<Vec<usize>, String> {
	let output = Command::new("swaymsg")
		.args(["-t", "get_outputs"])
		.output()
		.map_err(|e| format!("Failed to run swaymsg: {}", e))?;

	if !output.status.success() {
		return Err("swaymsg failed".to_string());
	}

	let json_str = String::from_utf8(output.stdout).map_err(|e| format!("Invalid UTF-8: {}", e))?;

	let outputs: serde_json::Value =
		serde_json::from_str(&json_str).map_err(|e| format!("Failed to parse JSON: {}", e))?;

	let outputs_array = outputs.as_array().ok_or("Expected array of outputs")?;

	// Get active outputs sorted by position
	let mut active_outputs: Vec<_> = outputs_array
		.iter()
		.filter(|o| o["active"].as_bool().unwrap_or(false))
		.collect();

	active_outputs.sort_by_key(|o| {
		let x = o["rect"]["x"].as_i64().unwrap_or(0);
		let y = o["rect"]["y"].as_i64().unwrap_or(0);
		(x, y)
	});

	Ok((0..active_outputs.len()).collect())
}

fn open_eww_windows(monitor_index: usize) -> Result<(), String> {
	let windows = ["bar", "btc_line_lower", "btc_line_upper", "todo_blocker"];

	for window in windows {
		Command::new("eww")
			.args(["open", window, "--screen", &monitor_index.to_string()])
			.status()
			.map_err(|e| format!("Failed to open {}: {}", window, e))?;
	}

	Ok(())
}

fn run() -> Result<(), String> {
	let args = Args::parse();

	match args.command {
		Commands::OnFocused => {
			let monitor_index = get_focused_monitor_index()?;
			println!("Opening eww windows on monitor {}", monitor_index);
			open_eww_windows(monitor_index)
		}
		Commands::All => {
			let monitor_indices = get_all_monitor_indices()?;
			println!("Opening eww windows on {} monitors", monitor_indices.len());
			for index in monitor_indices {
				open_eww_windows(index)?;
			}
			Ok(())
		}
	}
}

fn main() {
	if let Err(e) = run() {
		eprintln!("Error: {}", e);
		std::process::exit(1);
	}
}
