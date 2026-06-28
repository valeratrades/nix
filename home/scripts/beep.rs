#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
v_utils = { version = "2.15.54", default-features = false }
---

use clap::Parser;
use std::process::Command;
use std::path::PathBuf;
use std::str::FromStr;
use v_utils::other::percent::{Percent, PercentU};

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

	/// Absolute output volume (e.g. `40` or `40%`). When omitted, the sound plays at
	/// the system's current master volume, untouched. When given, master is pinned to
	/// exactly this value for the beep, then restored. Values outside 0-100% are rejected.
	#[arg(short, long, value_parser = parse_percent)]
	volume: Option<PercentU>,

	/// Headphone safety ceiling (e.g. `30%`). Only applies when headphones/headset are
	/// the active output. The beep never plays above this: if the level that would
	/// otherwise play (explicit --volume, else the current master) exceeds it, it plays
	/// at the cap instead. Ignored on speakers.
	#[arg(long, value_parser = parse_percent, default_value = "15")]
	max_absolute_headphones_volume: PercentU,
}

const SINK: &str = "@DEFAULT_AUDIO_SINK@";

fn parse_percent(s: &str) -> Result<PercentU, Box<dyn std::error::Error + Send + Sync>> {
	let p = Percent::from_str(s).map_err(|e| e.to_string())?;
	let pu = PercentU::try_from(p).map_err(|e| e.to_string())?;
	Ok(pu)
}

/// Current master as a fraction (0.0-1.0+). Exits on failure — we must not change
/// master if we can't read it back to restore it.
fn get_master() -> f64 {
	let out = Command::new("wpctl").args(["get-volume", SINK]).output();
	let stdout = match out {
		Ok(o) if o.status.success() => o.stdout,
		Ok(o) => {
			eprintln!("wpctl get-volume failed: {}", String::from_utf8_lossy(&o.stderr));
			std::process::exit(1);
		}
		Err(e) => {
			eprintln!("Error reading master volume: {e}");
			std::process::exit(1);
		}
	};
	// "Volume: 0.13" (possibly trailing " [MUTED]")
	let text = String::from_utf8(stdout).expect("wpctl emits utf8");
	text.split_whitespace().nth(1)
		.expect("wpctl prints 'Volume: <n>'")
		.parse::<f64>()
		.expect("wpctl prints a float")
}

fn set_master(v: f64) {
	let v = format!("{v}");
	let status = Command::new("wpctl").args(["set-volume", SINK, &v]).status();
	match status {
		Ok(s) if s.success() => {}
		Ok(_) => {
			eprintln!("wpctl set-volume {v} failed");
			std::process::exit(1);
		}
		Err(e) => {
			eprintln!("Error setting master volume: {e}");
			std::process::exit(1);
		}
	}
}

fn pactl(args: &[&str]) -> String {
	let out = Command::new("pactl").args(args).output();
	match out {
		Ok(o) if o.status.success() => String::from_utf8(o.stdout).expect("pactl emits utf8"),
		Ok(o) => {
			eprintln!("pactl {args:?} failed: {}", String::from_utf8_lossy(&o.stderr));
			std::process::exit(1);
		}
		Err(e) => {
			eprintln!("Error running pactl: {e}");
			std::process::exit(1);
		}
	}
}

/// True when the default sink routes to headphones/headset (incl. bluetooth).
fn headphones_active() -> bool {
	let default = pactl(&["get-default-sink"]);
	let name = default.trim();
	if name.contains("bluez") {
		return true;
	}
	let list = pactl(&["list", "sinks"]);
	let mut in_block = false;
	for line in list.lines() {
		let t = line.trim();
		if let Some(n) = t.strip_prefix("Name: ") {
			in_block = n == name;
		}
		if in_block {
			if let Some(p) = t.strip_prefix("Active Port: ") {
				return p.contains("headphone") || p.contains("headset");
			}
		}
	}
	false
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
		// Resolve the absolute master level to pin for this beep. None => leave the
		// system untouched (default path). The headphone cap can force a pin even when
		// no --volume was given, if the current master would exceed the ceiling.
		let mut target: Option<f64> = args.volume.map(|p| *p);

		if headphones_active() {
			let cap = *args.max_absolute_headphones_volume;
			match target {
				// Explicit request above the cap is a user error — refuse, don't silently quiet it.
				Some(v) if v > cap => {
					eprintln!("--volume {}% exceeds headphone cap {}%; refusing to play", v * 100.0, cap * 100.0);
					std::process::exit(1);
				}
				Some(_) => {}
				// No explicit volume: clamp the ambient master down to the cap if it's too loud.
				None => target = (get_master() > cap).then_some(cap),
			}
		}

		let saved_master = target.map(|t| {
			let saved = get_master();
			set_master(t);
			saved
		});

		let sound_result = Command::new("ffplay")
			.args(["-nodisp", "-autoexit", "-loglevel", "quiet", args.sound_file.to_str().unwrap()])
			.output();

		if let Some(saved) = saved_master {
			set_master(saved);
		}

		if let Err(e) = sound_result {
			eprintln!("Error playing sound: {e}");
			std::process::exit(1);
		}
	}
}
