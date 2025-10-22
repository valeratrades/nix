#!/usr/bin/env nix
---cargo
#! nix shell --impure --expr ``
#! nix let rust_flake = builtins.getFlake ''github:oxalica/rust-overlay'';
#! nix     nixpkgs_flake = builtins.getFlake ''nixpkgs'';
#! nix     pkgs = import nixpkgs_flake {
#! nix       system = builtins.currentSystem;
#! nix       overlays = [rust_flake.overlays.default];
#! nix     };
#! nix     toolchain = pkgs.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default.override {
#! nix       extensions = ["rust-src"];
#! nix     });
#! nix
#! nix in toolchain
#! nix ``
#! nix --command sh -c ``cargo -Zscript "$0" "$@"``

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::Parser;
use std::{env, path::PathBuf, process::Command};

/// Move latest download to a destination
#[derive(Parser, Debug)]
#[command(name = "mvd")]
#[command(about = "Move latest download to predefined or custom locations")]
struct Args {
	/// Move to Papers directory
	#[arg(short, long, group = "location")]
	paper: bool,

	/// Move to Books directory
	#[arg(short, long, group = "location")]
	book: bool,

	/// Move to Notes directory
	#[arg(short, long, group = "location")]
	notes: bool,

	/// Move to Courses directory
	#[arg(short, long, group = "location")]
	courses: bool,

	/// Move to TwitterThreads directory
	#[arg(short, long, group = "location")]
	twitter: bool,

	/// Move to Wine downloads directory
	#[arg(short, long, group = "location")]
	wine: bool,

	/// Move to Images directory
	#[arg(short, long, group = "location")]
	images: bool,

	/// Move screenshots to trading/strats directory
	#[arg(long, group = "location")]
	screenshot_trading: bool,

	/// Move screenshots to Images directory
	#[arg(long, group = "location")]
	screenshot_images: bool,

	/// Direct path to move to (if no flag is specified)
	#[arg(group = "location")]
	path: Option<PathBuf>,

	/// Subdirectory within the destination (only for flagged locations)
	subpath: Option<String>,

	/// New name for the file
	new_name: Option<String>,
}

fn main() {
	let args = Args::parse();

	let home = match env::var("HOME") {
		Ok(val) => PathBuf::from(val),
		Err(_) => {
			eprintln!("Error: HOME environment variable not set");
			std::process::exit(1);
		}
	};

	let (from, mut to_dir) = if args.paper {
		(home.join("Downloads"), home.join("Documents/Papers"))
	} else if args.book {
		(home.join("Downloads"), home.join("Documents/Books"))
	} else if args.notes {
		(home.join("Downloads"), home.join("Documents/Notes"))
	} else if args.courses {
		(home.join("Downloads"), home.join("Documents/Courses"))
	} else if args.twitter {
		(home.join("Downloads"), home.join("Documents/TwitterThreads"))
	} else if args.wine {
		(home.join("Downloads"), home.join(".wine/drive_c/users/v/Downloads"))
	} else if args.images {
		(home.join("Downloads"), home.join("Images"))
	} else if args.screenshot_trading {
		(home.join("tmp/Screenshots"), home.join("trading/strats"))
	} else if args.screenshot_images {
		(home.join("tmp/Screenshots"), home.join("Images"))
	} else if let Some(path) = args.path {
		let mut to_dir = path;
		if !to_dir.is_absolute() {
			to_dir = home.join(to_dir);
		}
		(home.join("Downloads"), to_dir)
	} else {
		eprintln!("Error: No destination specified");
		std::process::exit(1);
	};

	// Add subpath if provided
	if let Some(subpath) = args.subpath {
		to_dir = to_dir.join(subpath);
	}

	if !to_dir.exists() {
		eprintln!("Error: Directory {:?} does not exist", to_dir);
		std::process::exit(1);
	}

	let latest_file: Option<PathBuf> = {
		let output = Command::new("ls").arg("-t").arg(&from).output().expect("Failed to execute ls command");

		if !output.status.success() {
			eprintln!("Error executing ls command: {}", String::from_utf8_lossy(&output.stderr));
			std::process::exit(1);
		}

		let out_str = String::from_utf8_lossy(&output.stdout);
		let first_line = out_str.lines().next().unwrap_or_default();

		if first_line.is_empty() {
			eprintln!("No files found in {from:?}");
			std::process::exit(1);
		}

		Some(from.join(first_line))
	};

	let destination = match args.new_name {
		Some(fname) => to_dir.join(fname),
		None => to_dir,
	};

	match latest_file {
		Some(from_path) => {
			let status = Command::new("mv").arg(&from_path).arg(&destination).status().expect("Failed to execute mv command");

			if status.success() {
				println!("Moved {from_path:?} to {destination:?}");
			} else {
				eprintln!("Error moving file. mv command failed with status: {}", status);
				std::process::exit(1);
			}
		}
		None => {
			eprintln!("No files found in {from:?}");
			std::process::exit(1);
		}
	}
}
