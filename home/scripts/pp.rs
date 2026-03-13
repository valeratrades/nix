#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::Parser;
use std::io::{self, IsTerminal, Write};
use std::process::{Command, exit};

/// Play audio with mpv at a given speed, with volume safety check
#[derive(Parser)]
#[command(name = "pp")]
struct Args {
	/// Playback speed
	speed: f64,

	/// Path to audio file or playlist
	file: String,
}

struct VolumeState {
	level: f64,
	muted: bool,
}

fn get_volume() -> VolumeState {
	let output = Command::new("wpctl")
		.args(["get-volume", "@DEFAULT_AUDIO_SINK@"])
		.output()
		.unwrap_or_else(|e| {
			eprintln!("Failed to run wpctl: {e}");
			exit(1);
		});
	let stdout = String::from_utf8_lossy(&output.stdout);
	// Format: "Volume: 0.15" or "Volume: 0.15 [MUTED]"
	let trimmed = stdout.trim();
	let muted = trimmed.contains("[MUTED]");
	let vol_str = trimmed
		.strip_prefix("Volume: ")
		.unwrap_or_else(|| {
			eprintln!("Unexpected wpctl output: {stdout}");
			exit(1);
		})
		.split_whitespace()
		.next()
		.unwrap();
	let level = vol_str.parse::<f64>().unwrap_or_else(|e| {
		eprintln!("Failed to parse volume '{vol_str}': {e}");
		exit(1);
	});
	VolumeState { level, muted }
}

fn main() {
	let args = Args::parse();

	let vol = get_volume();
	if vol.level > 0.5 && !vol.muted && io::stdin().is_terminal() {
		let pct = (vol.level * 100.0).round() as u32;
		print!("Volume is at {pct}%. Continue? [y/N] ");
		io::stdout().flush().unwrap();
		let mut input = String::new();
		io::stdin().read_line(&mut input).unwrap();
		if !input.trim().eq_ignore_ascii_case("y") {
			exit(1);
		}
	}

	let status = Command::new("mpv")
		.args([
			"--no-terminal",
			"--no-video",
			"--loop-file",
			"--loop-playlist",
			&format!("--speed={}", args.speed),
			&args.file,
		])
		.status()
		.unwrap_or_else(|e| {
			eprintln!("Failed to run mpv: {e}");
			exit(1);
		});

	exit(status.code().unwrap_or(1));
}
