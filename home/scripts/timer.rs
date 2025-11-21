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
---

//TODO!: switch to using v_utils::Timelike for time parsing
use clap::Parser;
use std::{process::Command, thread::sleep, time::Duration};

/// Countdown timer with visual feedback and notifications
#[derive(Parser, Debug)]
#[command(name = "timer")]
#[command(about = "Countdown timer with visual feedback and notifications")]
struct Args {
	/// Time in seconds or in format "mm:ss"
	time: String,

	/// Quiet mode (shows persistent notification instead of beeping)
	#[arg(short, long)]
	quiet: bool,
}

fn parse_time(input: &str) -> Result<i32, String> {
	if input.contains(':') {
		let parts: Vec<&str> = input.split(':').collect();
		if parts.len() != 2 {
			return Err("Time format must be mm:ss".to_string());
		}
		let mins: i32 = parts[0].parse::<i32>().map_err(|e| e.to_string())?;
		let secs: i32 = parts[1].parse::<i32>().map_err(|e| e.to_string())?;
		Ok(mins * 60 + secs)
	} else {
		input.parse::<i32>().map_err(|e| e.to_string())
	}
}

fn timer(args: &Args) -> Result<(), String> {
	let mut left = parse_time(&args.time)?;

	while left > 0 {
		let mins = left / 60;
		let secs = left % 60;
		let formatted_secs = format!("{:02}", secs);
		Command::new("eww")
			.args(["update", &format!("timer={mins}:{formatted_secs}")])
			.status()
			.map_err(|e| e.to_string())?;
		sleep(Duration::from_secs(1));
		left -= 1;
	}

	Command::new("eww")
        .args(["update", "timer="]) // eww things, doing `timer=\"\"` literally sets it to "\"\""
        .status()
        .map_err(|e| e.to_string())?;

	if args.quiet {
		Command::new("notify-send").args(["timer finished", "-t", "2147483647"]).status().map_err(|e| e.to_string())?;
	} else {
		Command::new("fish").args(["-c", "beep --long 600 time"]).status().map_err(|e| e.to_string())?;
	}

	Ok(())
}

fn main() {
	let args = Args::parse();
	if let Err(e) = timer(&args) {
		eprintln!("{e}");
		std::process::exit(1);
	}
}
