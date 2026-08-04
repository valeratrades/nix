#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::{Parser, ValueEnum};
use std::fs;
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const PLATFORM_PROFILE: &str = "/sys/firmware/acpi/platform_profile";
const PLATFORM_PROFILE_CHOICES: &str = "/sys/firmware/acpi/platform_profile_choices";
const CPU_BOOST: &str = "/sys/devices/system/cpu/cpufreq/boost";
const CPUFREQ: &str = "/sys/devices/system/cpu/cpufreq";

/// The declared baseline scaling_max_freq, in kHz. thermal-guard restores to *this* after an
/// excursion rather than to the hardware ceiling, so a hot spell cannot silently undo a chosen mode.
/// Single source of truth for "what this machine should be doing when it is not thermally stressed".
const BASE_FREQ: &str = "/run/optimize_for.base-freq";

/// NB: platform_profile is a *power limit* knob on this EC (PPT/STAPM), which happens to carry the
/// fan curve with it — the two cannot be separated. legion_cli's maximumfanspeed is the documented
/// way to pin fans independently, but this firmware silently ignores it (enable reads back False),
/// so "performance" remains the only way to get max airflow, and it necessarily raises the power
/// limits too.
///
/// No mode caps frequency below the hardware ceiling. schedutil already scales the cores with
/// demand, down to a 400 MHz floor, so a standing cap does nothing for a browsing machine and bites
/// only during the work that is actually wanted. Holding temperature down is thermal-guard's job,
/// applied on measured heat rather than pre-emptively.
#[derive(Debug, Clone, Copy, ValueEnum)]
enum Mode {
	/// Boost off, fans max (cool & preserve hardware)
	Longevity,
	/// Boost off, fans quiet (silent operation)
	Quiet,
	/// Boost on, fans max (full power)
	Performance,
	/// Show current status
	Status,
}

impl Mode {
	/// (boost, platform_profile); None for Status, which changes nothing
	fn settings(self) -> Option<(bool, &'static str)> {
		match self {
			Mode::Longevity => Some((false, "performance")),
			Mode::Quiet => Some((false, "quiet")),
			Mode::Performance => Some((true, "performance")),
			Mode::Status => None,
		}
	}
}

/// Prior state, reinstated on drop, so a scoped run cannot leave the machine boosted.
struct Restore {
	boost: bool,
	profile: String,
	max_freq: u64,
}

impl Drop for Restore {
	fn drop(&mut self) {
		apply(self.boost, &self.profile, self.max_freq);
	}
}

#[derive(Parser)]
#[command(name = "optimize_for")]
#[command(about = "Optimize system for longevity, quiet operation, or performance")]
struct Args {
	mode: Mode,
	/// Cap the CPU at this percentage of the hardware ceiling. Defaults to uncapped.
	#[arg(long, default_value_t = 100, value_parser = clap::value_parser!(u64).range(1..=100))]
	freq_pct: u64,
	/// Apply the mode only while this command runs, then restore the previous state.
	/// e.g. `optimize_for performance -- cargo b`
	#[arg(last = true, num_args = 1..)]
	cmd: Vec<String>,
}

fn main() {
	let args = Args::parse();

	let Some((boost, profile)) = args.mode.settings() else {
		show_status();
		return;
	};
	let name = args.mode.to_possible_value().expect("Status is the only skipped variant").get_name().to_string();

	// Boost has to land before the ceiling is read: amd-pstate swings cpuinfo_max_freq between the
	// base clock (2501 MHz) and the boost clock (5461 MHz) according to it, so a percentage read
	// beforehand would be taken against the wrong number.
	let restore = (!args.cmd.is_empty()).then(|| Restore { boost: read_boost(), profile: read_profile(), max_freq: read_max_freq() });
	set_boost(boost);
	let max_freq = read_ceiling() * args.freq_pct / 100;
	apply(boost, profile, max_freq);

	let scoped = if restore.is_some() { " (scoped)" } else { "" };
	println!("{name}{scoped}: boost {}, fans {profile}, cpu up to {} MHz", if boost { "on" } else { "off" }, max_freq / 1000);

	let Some(cmd) = args.cmd.split_first() else { return };

	// ponytail: Drop covers normal exit and panic, but not SIGINT — Ctrl-C kills the whole process
	// group, so the parent dies without restoring and boost stays on until the next boot (the
	// legion-longevity unit re-clears it). Reach for a signal handler only if that proves annoying.
	let status = Command::new(cmd.0).args(cmd.1).status().unwrap_or_else(|e| panic!("failed to run `{}`: {e}", cmd.0));

	drop(restore); // std::process::exit skips destructors
	std::process::exit(status.code().unwrap_or_else(|| 128 + status.signal().expect("no exit code only when signalled")));
}

fn apply(boost: bool, profile: &str, max_freq: u64) {
	set_boost(boost);
	set_profile(profile);
	set_max_freq(max_freq);
	fs::write(BASE_FREQ, max_freq.to_string()).expect("/run is writable; optimize_for runs as root");
}

fn policies() -> impl Iterator<Item = PathBuf> {
	fs::read_dir(CPUFREQ)
		.expect("cpufreq sysfs present under amd-pstate")
		.map(|e| e.expect("cpufreq sysfs entries are readable").path())
		.filter(|p| p.file_name().is_some_and(|n| n.to_string_lossy().starts_with("policy")))
}

fn read_ceiling() -> u64 {
	let path = Path::new(CPUFREQ).join("policy0/cpuinfo_max_freq");
	fs::read_to_string(&path).expect("policy0 always exists").trim().parse().expect("sysfs reports frequency in kHz")
}

fn read_max_freq() -> u64 {
	let path = Path::new(CPUFREQ).join("policy0/scaling_max_freq");
	fs::read_to_string(&path).expect("policy0 always exists").trim().parse().expect("sysfs reports frequency in kHz")
}

fn read_boost() -> bool {
	fs::read_to_string(CPU_BOOST).expect("udev grants wheel rw on cpufreq/boost").trim() == "1"
}

fn read_profile() -> String {
	fs::read_to_string(PLATFORM_PROFILE).expect("legion_laptop force=1 exposes platform_profile").trim().to_string()
}

fn set_max_freq(khz: u64) {
	for policy in policies() {
		let path = policy.join("scaling_max_freq");
		fs::write(&path, khz.to_string()).unwrap_or_else(|e| panic!("failed to cap {}: {e}", path.display()));
	}
}

fn set_boost(enabled: bool) {
	fs::write(CPU_BOOST, if enabled { "1" } else { "0" }).expect("udev grants wheel rw on cpufreq/boost");
}

fn set_profile(profile: &str) {
	fs::write(PLATFORM_PROFILE, profile).expect("legion_laptop force=1 exposes platform_profile");
}

fn show_status() {
	let ceiling = read_ceiling();
	let max_freq = read_max_freq();

	println!("boost:    {}", if read_boost() { "on" } else { "off" });
	println!("fans:     {}", read_profile());
	println!("cpu:      {} MHz of {} MHz ({}%)", max_freq / 1000, ceiling / 1000, max_freq * 100 / ceiling);
	println!("profiles: {}", fs::read_to_string(PLATFORM_PROFILE_CHOICES).expect("legion_laptop exposes choices").trim());
}
