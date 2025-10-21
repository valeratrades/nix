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
//TODO!!!: rewrite with clap

use std::{env, path::PathBuf, process::Command};

static HELP: &str = r#"
mvd - move latest download
Usage:
  mvd PATH                          # moves to specified path directly
  mvd [OPTION] [SUBPATH] [NEW_NAME] # moves to predefined location, optionally with subpath, optionally renaming
Examples:
  mvd ~/Documents/Books/tmp/ # moves directly to specified path
  mvd -p research            # moves to $HOME/Documents/Papers/research
  mvd -b                     # moves to $HOME/Documents/Books
	mvd -b "" new_name.pdf     # because we don't have clap, 2nd arg will always be subpath - careful.
Options:
  -h, --help             Show this help message
  -p, --paper            Move to Papers directory
  -b, --book             Move to Books directory
  -n, --notes            Move to Notes directory
  -c, --courses          Move to Courses directory
  -t, --twitter          Move to TwitterThreads directory
  -w, --wine             Move to Wine downloads directory
  -i, --images           Move to Images directory
  --st, --screenshot-trading    Move to trading/strats directory
  --si, --screenshot-images     Move to Images/Screenshots directory
"#;

fn main() {
	let mut args = env::args().skip(1)/*discard exe name*/;
	if args.len() == 0 {
		eprintln!("Usage: mvd [OPTION] [SUBPATH] or mvd PATH");
		eprintln!("Try 'mvd --help' for more information.");
		std::process::exit(1);
	}
	dbg!(&args);

	let home = match env::var("HOME") {
		Ok(val) => PathBuf::from(val),
		Err(_) => {
			eprintln!("Error: HOME environment variable not set");
			std::process::exit(1);
		}
	};

	let (from, to_dir) = match args.next().expect("checked earlier").as_str() {
		"-h" | "--help" => {
			println!("{HELP}");
			std::process::exit(0);
		}
		"-p" | "--paper" => {
			let subfolder = args.next().unwrap_or_default();
			(home.join("Downloads"), home.join("Documents/Papers").join(subfolder))
		}
		"-b" | "--book" => {
			let subfolder = args.next().unwrap_or_default();
			(home.join("Downloads"), home.join("Documents/Books").join(subfolder))
		}
		"-n" | "--notes" => {
			let subfolder = args.next().unwrap_or_default();
			(home.join("Downloads"), home.join("Documents/Notes").join(subfolder))
		}
		"-c" | "--courses" => {
			let subfolder = args.next().unwrap_or_default();
			(home.join("Downloads"), home.join("Documents/Courses").join(subfolder))
		}
		"-t" | "--twitter" => {
			let subfolder = args.next().unwrap_or_default();
			(home.join("Downloads"), home.join("Documents/TwitterThreads").join(subfolder))
		}
		"-w" | "--wine" => {
			let subfolder = args.next().unwrap_or_default();
			(home.join("Downloads"), home.join(".wine/drive_c/users/v/Downloads").join(subfolder))
		}
		"-i" | "--images" => {
			let subfolder = args.next().unwrap_or_default();
			(home.join("Downloads"), home.join("Images").join(subfolder))
		}
		"-s" | "--screenshot" => {
			let subfolder = args.next().unwrap_or_default();
			(home.join("tmp/Screenshots"), home.join("trading/strats").join(subfolder))
		}
		"--st" | "--screenshot-trading" => {
			let subfolder = args.next().unwrap_or_default();
			(home.join("tmp/Screenshots"), home.join("trading/strats").join(subfolder))
		}
		"--si" | "--screenshot-images" => {
			let subfolder = args.next().unwrap_or_default();
			(home.join("tmp/Screenshots"), home.join(subfolder))
		}
		path => {
			// treat as direct path
			let mut to_dir = PathBuf::from(path);
			if !to_dir.is_absolute() {
				to_dir = home.join(path);
			}
			(home.join("Downloads"), to_dir)
		}
	};
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

	let destination = match args.next() {
		Some(fname) => to_dir.join(fname),
		None => to_dir,
	};
	dbg!(&destination);

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
