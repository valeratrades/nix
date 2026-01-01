#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::Parser;
use std::process::Command;
use std::path::PathBuf;

/// Play a sound and show a notification
#[derive(Parser, Debug)]
#[command(name = "beep")]
#[command(about = "Play a sound and show a notification")]
struct Args {
	/// Path to the sound file to play
	sound_file: PathBuf,

	/// Message to display in notification
	message: Vec<String>,

	/// Show notification for a long time (10 minutes) or specific number of seconds
	#[arg(short, long, value_name = "SECONDS")]
	long: Option<Option<u32>>,

	/// Don't play sound, only show notification
	#[arg(short, long)]
	quiet: bool,
}

fn main() {
	let args = Args::parse();

	let message = if args.message.is_empty() {
		"beep".to_string()
	} else {
		args.message.join(" ")
	};

	// Determine notification timeout
	let timeout_ms = match args.long {
		Some(Some(seconds)) => seconds * 1000, // User specified exact seconds
		Some(None) => 600000,                   // -l flag without value: 10 minutes
		None => 5000,                           // No -l flag: default timeout (5 seconds for notify-send)
	};

	// Show notification
	let notify_result = if args.long.is_some() {
		Command::new("notify-send")
			.args(["-t", &timeout_ms.to_string(), &message])
			.status()
	} else {
		Command::new("notify-send")
			.arg(&message)
			.status()
	};

	if let Err(e) = notify_result {
		eprintln!("Error showing notification: {e}");
		std::process::exit(1);
	}

	// Play sound unless quiet mode
	if !args.quiet {
		let sound_result = Command::new("ffplay")
			.args(["-nodisp", "-autoexit", "-loglevel", "quiet", args.sound_file.to_str().unwrap()])
			.output();

		if let Err(e) = sound_result {
			eprintln!("Error playing sound: {e}");
			std::process::exit(1);
		}
	}
}
