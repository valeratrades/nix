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

fn sanitize_filename(filename: &str) -> String {
	// Hardcoded patterns to remove from filenames
	let patterns_to_remove = [
		"SpotiDown.App - ",
	];

	let mut result = filename.to_string();
	for pattern in &patterns_to_remove {
		result = result.replace(pattern, "");
	}

	// Replace spaces with underscores
	result.replace(' ', "_")
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

	// Extract filename from path if it looks like a file
	let mut extracted_filename: Option<String> = None;

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

		// If the path appears to be a file (has an extension), extract the directory
		// This allows users to specify the full destination path including filename
		if to_dir.extension().is_some() {
			if let Some(filename) = to_dir.file_name() {
				extracted_filename = Some(filename.to_string_lossy().to_string());
			}
			if let Some(parent) = to_dir.parent() {
				to_dir = parent.to_path_buf();
			}
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

	match latest_file {
		Some(from_path) => {
			// Determine the final destination with filename
			let final_destination = match args.new_name.or(extracted_filename) {
				// If explicit filename provided, use it as-is (don't sanitize)
				Some(fname) => to_dir.join(fname),
				// If no explicit filename, sanitize the original filename
				None => {
					if let Some(original_filename) = from_path.file_name() {
						let sanitized_name = sanitize_filename(&original_filename.to_string_lossy());
						to_dir.join(sanitized_name)
					} else {
						to_dir
					}
				}
			};

			let status = Command::new("mv").arg(&from_path).arg(&final_destination).status().expect("Failed to execute mv command");

			if status.success() {
				println!("Moved {from_path:?} to {final_destination:?}");
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
