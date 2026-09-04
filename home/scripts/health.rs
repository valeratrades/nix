#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::Parser;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread::sleep;
use std::time::{Duration, Instant};

const CGROUP_ROOT: &str = "/sys/fs/cgroup";
const HWMON: &str = "/sys/class/hwmon";
const EWW_YUCK: &str = "/home/v/nix/home/config/eww/eww.yuck";

/// Where idle power is going: CPU by cgroup, spawn rate, thermals.
///
/// Everything is a live delta over --sample seconds, not a since-boot average: a machine that was
/// busy an hour ago and is quiet now reads as quiet.
#[derive(Parser)]
#[command(name = "health", about = "Idle-load and thermal report")]
struct Args {
	/// Seconds to sample rates over
	#[arg(short, long, default_value_t = 3.0)]
	sample: f64,

	/// Also time every eww defpoll. Spawns each poll's command once, so it is off by default.
	#[arg(long)]
	polls: bool,

	/// Cgroups to list
	#[arg(short = 'n', long, default_value_t = 12)]
	top: usize,
}

fn main() {
	let args = Args::parse();
	let window = Duration::from_secs_f64(args.sample);

	let cg0 = cgroup_usage();
	let forks0 = counter("processes");
	let ctxt0 = counter("ctxt");
	sleep(window);
	let cg1 = cgroup_usage();
	let forks1 = counter("processes");
	let ctxt1 = counter("ctxt");

	let secs = args.sample;
	report_cpu(&cg0, &cg1, secs, args.top);
	println!();
	println!("  {:<26} {:>10.0} /s", "process spawns", (forks1 - forks0) as f64 / secs);
	println!("  {:<26} {:>10.0} /s", "context switches", (ctxt1 - ctxt0) as f64 / secs);
	println!();
	report_thermals();

	if args.polls {
		println!();
		report_polls();
	}
}

// ---- cpu ----

/// usage_usec for every cgroup that has cpu.stat. read_dir failures are skipped rather than
/// reported: cgroups appear and vanish while this walks, and unreadable subtrees are normal for a
/// non-root caller. A cgroup that exists and is readable but has no usage_usec is a real
/// inconsistency, so that line panics instead.
fn cgroup_usage() -> HashMap<PathBuf, u64> {
	let mut out = HashMap::new();
	let mut stack = vec![PathBuf::from(CGROUP_ROOT)];
	while let Some(dir) = stack.pop() {
		let Ok(entries) = fs::read_dir(&dir) else { continue };
		for e in entries.flatten() {
			if e.path().is_dir() {
				stack.push(e.path());
			}
		}
		let stat = dir.join("cpu.stat");
		let Ok(text) = fs::read_to_string(&stat) else { continue };
		let usec = text
			.lines()
			.find_map(|l| l.strip_prefix("usage_usec "))
			.unwrap_or_else(|| panic!("{} exists but has no usage_usec", stat.display()))
			.trim()
			.parse::<u64>()
			.expect("usage_usec is a plain integer");
		out.insert(dir, usec);
	}
	out
}

fn report_cpu(before: &HashMap<PathBuf, u64>, after: &HashMap<PathBuf, u64>, secs: f64, top: usize) {
	let mut delta: HashMap<&Path, u64> = HashMap::new();
	for (path, end) in after {
		let Some(start) = before.get(path) else { continue }; // cgroup born mid-sample: no baseline
		delta.insert(path.as_path(), end.saturating_sub(*start));
	}

	// A parent's usage_usec includes its descendants', so charge each cgroup only what its own
	// processes used. saturating: the two samples are not atomic, so a child can briefly
	// out-account its parent.
	let mut own = delta.clone();
	for (path, d) in &delta {
		if let Some(parent) = path.parent() {
			if let Some(p) = own.get_mut(parent) {
				*p = p.saturating_sub(*d);
			}
		}
	}

	let total: u64 = own.values().sum();
	let mut rows: Vec<_> = own.into_iter().filter(|(_, d)| *d > 0).collect();
	rows.sort_by_key(|(_, d)| std::cmp::Reverse(*d));

	println!("CPU over {secs:.0}s — % of ONE core, charged to the cgroup that spent it");
	println!();
	for (path, d) in rows.iter().take(top) {
		println!("  {:<40} {:>7.2}%", short(path), pct(*d, secs));
	}
	println!("  {:-<40} {:->8}", "", "");
	println!("  {:<40} {:>7.2}%   ({:.1} of {} threads)", "total", pct(total, secs), pct(total, secs) / 100.0, nproc());
}

fn pct(usec: u64, secs: f64) -> f64 {
	usec as f64 / 1e6 / secs * 100.0
}

fn short(path: &Path) -> String {
	let s = path.to_string_lossy();
	let s = s.strip_prefix(CGROUP_ROOT).unwrap_or(&s).trim_start_matches('/');
	let s = s.replace("user.slice/user-1000.slice/user@1000.service/", "");
	let s = s.replace("user.slice/user-1000.slice/", "");
	let s = s.replace("system.slice/", "sys:");
	if s.is_empty() { "/ (root)".into() } else { s }
}

fn counter(key: &str) -> u64 {
	let stat = fs::read_to_string("/proc/stat").expect("/proc/stat always readable");
	stat.lines()
		.find_map(|l| l.strip_prefix(&format!("{key} ")))
		.unwrap_or_else(|| panic!("/proc/stat has no {key} line"))
		.trim()
		.parse()
		.expect("counter is a plain integer")
}

fn nproc() -> usize {
	fs::read_to_string("/proc/cpuinfo")
		.expect("/proc/cpuinfo always readable")
		.lines()
		.filter(|l| l.starts_with("processor"))
		.count()
}

// ---- thermals ----

fn hwmon_by_name(name: &str) -> Option<PathBuf> {
	for e in fs::read_dir(HWMON).expect("/sys/class/hwmon always present").flatten() {
		if fs::read_to_string(e.path().join("name")).is_ok_and(|n| n.trim() == name) {
			return Some(e.path());
		}
	}
	None
}

fn num(path: &Path) -> Option<i64> {
	fs::read_to_string(path).ok()?.trim().parse().ok()
}

fn report_thermals() {
	println!("THERMALS");
	println!();

	if let Some(k10) = hwmon_by_name("k10temp") {
		if let Some(t) = num(&k10.join("temp1_input")) {
			println!("  {:<26} {:>8.1} C", "CPU (Tctl)", t as f64 / 1000.0);
		}
	}
	if let Some(gpu) = hwmon_by_name("amdgpu") {
		if let Some(t) = num(&gpu.join("temp1_input")) {
			println!("  {:<26} {:>8.1} C", "iGPU", t as f64 / 1000.0);
		}
		// power1_input, not power1_average: this driver only exposes the instantaneous one.
		if let Some(p) = num(&gpu.join("power1_input")) {
			println!("  {:<26} {:>8.2} W", "SoC package", p as f64 / 1e6);
		}
	}
	if let Some(fans) = hwmon_by_name("lenovo_wmi_other") {
		let rpm: Vec<String> = (1..=4)
			.filter_map(|i| num(&fans.join(format!("fan{i}_input"))))
			.map(|r| r.to_string())
			.collect();
		if !rpm.is_empty() {
			println!("  {:<26} {:>8} RPM", "fans", rpm.join(" / "));
		}
	}

	if let Ok(p) = fs::read_to_string("/sys/firmware/acpi/platform_profile") {
		println!("  {:<26} {:>8}", "platform_profile", p.trim());
	}
	if let Ok(g) = fs::read_to_string("/sys/devices/system/cpu/cpufreq/policy0/scaling_governor") {
		println!("  {:<26} {:>8}", "governor", g.trim());
	}
	if let Ok(b) = fs::read_to_string("/sys/devices/system/cpu/cpufreq/boost") {
		println!("  {:<26} {:>8}", "boost", if b.trim() == "1" { "on" } else { "off" });
	}

	report_dgpu();

	for bat in ["BAT0", "BAT1"] {
		let dir = PathBuf::from("/sys/class/power_supply").join(bat);
		let Ok(status) = fs::read_to_string(dir.join("status")) else { continue };
		let draw = num(&dir.join("power_now")).map_or(String::from("-"), |p| format!("{:.2} W", p as f64 / 1e6));
		println!("  {:<26} {:>8}  ({})", format!("battery {bat}"), status.trim(), draw);
	}
}

/// The dGPU is the one consumer that can idle at several watts while reading as absent: with
/// powerManagement.finegrained off it never autosuspends, so `active` here is the normal state and
/// its draw is a standing cost, not a sign that something woke it.
fn report_dgpu() {
	let Ok(entries) = fs::read_dir("/sys/bus/pci/drivers/nvidia") else { return };
	for e in entries.flatten() {
		let Ok(status) = fs::read_to_string(e.path().join("power/runtime_status")) else { continue };
		let status = status.trim().to_string();
		let mut line = format!("  {:<26} {:>8}", "dGPU", status);
		if status == "active" {
			if let Ok(out) = Command::new("nvidia-smi")
				.args(["--query-gpu=power.draw,temperature.gpu", "--format=csv,noheader,nounits"])
				.output()
			{
				let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
				if let Some((w, t)) = s.split_once(", ") {
					line.push_str(&format!("  ({w} W, {t} C)"));
				}
			}
		}
		println!("{line}");
	}
}

// ---- eww polls ----

/// name, interval seconds, shell command
fn parse_polls() -> Vec<(String, f64, String)> {
	let text = fs::read_to_string(EWW_YUCK).expect("eww.yuck is checked in next to this repo");
	let mut out = Vec::new();
	for line in text.lines() {
		let line = line.trim();
		let Some(rest) = line.strip_prefix("(defpoll ") else { continue };
		let name = rest.split_whitespace().next().expect("defpoll always names a var").to_string();

		let Some(iv_at) = rest.find(":interval \"") else { continue }; // EWW_* builtins have no interval
		let iv_body = &rest[iv_at + ":interval \"".len()..];
		let iv_str = &iv_body[..iv_body.find('"').expect("interval literal is closed")];
		let secs = parse_interval(iv_str);

		// The command is the last string literal on the line; scan back over \" so a command that
		// quotes internally (date +\"...\") is not truncated.
		let after = &iv_body[iv_body.find('"').unwrap() + 1..];
		let Some(cmd) = last_string_literal(after) else { continue };
		out.push((name, secs, cmd));
	}
	out
}

fn parse_interval(s: &str) -> f64 {
	let (num, mult) = if let Some(n) = s.strip_suffix("ms") {
		(n, 0.001)
	} else if let Some(n) = s.strip_suffix('s') {
		(n, 1.0)
	} else if let Some(n) = s.strip_suffix('m') {
		(n, 60.0)
	} else {
		panic!("unrecognised eww interval unit: {s}")
	};
	num.parse::<f64>().unwrap_or_else(|_| panic!("interval is numeric: {s}")) * mult
}

fn last_string_literal(s: &str) -> Option<String> {
	let b: Vec<char> = s.chars().collect();
	let mut end = None;
	let mut i = b.len();
	while i > 0 {
		i -= 1;
		if b[i] == '"' && (i == 0 || b[i - 1] != '\\') {
			match end {
				None => end = Some(i),
				Some(e) => return Some(b[i + 1..e].iter().collect::<String>().replace("\\\"", "\"")),
			}
		}
	}
	None
}

fn report_polls() {
	println!("EWW POLLS — cost of one run, and what that costs standing at its interval");
	println!();
	let mut rows: Vec<(String, f64, f64, f64)> = Vec::new();
	for (name, interval, cmd) in parse_polls() {
		let started = Instant::now();
		let ran = Command::new("sh")
			.arg("-c")
			.arg(&cmd)
			.current_dir("/home/v/nix/home/config/eww")
			.output();
		let elapsed = started.elapsed().as_secs_f64();
		if ran.is_err() {
			continue; // a poll whose binary is absent on this host is not a health signal
		}
		rows.push((name, interval, elapsed, elapsed / interval * 100.0));
	}
	rows.sort_by(|a, b| b.3.total_cmp(&a.3));

	println!("  {:<32} {:>9} {:>10} {:>9}", "POLL", "INTERVAL", "PER RUN", "OF-CORE");
	for (name, interval, per_run, pct) in &rows {
		println!("  {name:<32} {interval:>8.1}s {per_run:>9.3}s {pct:>8.1}%");
	}
	println!("  {:-<32} {:->9} {:->10} {:->9}", "", "", "", "");
	println!("  {:<32} {:>9} {:>10} {:>8.1}%", "total", "", "", rows.iter().map(|r| r.3).sum::<f64>());
	println!();
	println!("  (wall time, so a poll that waits on IPC reads higher than its CPU cost)");
}
