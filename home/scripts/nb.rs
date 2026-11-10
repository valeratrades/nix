#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde_json = "1"
---

use clap::Parser;
use serde_json::Value;
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::time::Instant;

/// NixOS rebuild wrapper
#[derive(Parser, Debug)]
#[command(name = "nb")]
#[command(about = "NixOS rebuild wrapper with optional beep notifications")]
struct Args {
    /// Play beep sound before and after rebuild
    #[arg(short, long)]
    beep: bool,

    /// Enable debug mode with --show-trace and abort-on-warn
    #[arg(short = 'D', long)]
    debug: bool,

    /// Print where the time went (eval / substitute / build / switch) after the run, from nix's internal-json log
    #[arg(short, long)]
    timings: bool,

    /// Toggle sccache in cargo config (true/false). If omitted, leaves current value.
    #[arg(long)]
    sccache: Option<bool>,

    /// Additional arguments to pass to nixos-rebuild
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    extra_args: Vec<String>,
}

fn set_nix_var(var: &str, value: &str) {
    let vars_path = "/home/v/nix/vars/default.nix";
    let content = std::fs::read_to_string(vars_path).expect("Failed to read vars/default.nix");

    let whoami = Command::new("whoami").output().expect("Failed to run whoami");
    let username = String::from_utf8_lossy(&whoami.stdout).trim().to_string();
    let username_marker = format!("username = \"{username}\";");

    let pattern = format!("{var} = ");
    let mut in_my_block = false;
    let mut depth: i32 = 0;
    let mut replaced = false;
    let new_content = content
        .lines()
        .map(|line| {
            let trimmed = line.trim();
            if trimmed.contains(&username_marker) {
                in_my_block = true;
                depth = 0;
            }
            if in_my_block {
                depth += trimmed.matches('{').count() as i32;
                depth -= trimmed.matches('}').count() as i32;
                if depth <= 0 && replaced {
                    in_my_block = false;
                }
            }
            let t = line.trim_start();
            if in_my_block && t.starts_with(&pattern) && !t.starts_with('#') {
                replaced = true;
                let indent = &line[..line.len() - t.len()];
                format!("{indent}{var} = {value};")
            } else {
                line.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
        + if content.ends_with('\n') { "\n" } else { "" };
    if !replaced {
        panic!("'{var}' not found in {vars_path} for user '{username}'");
    }
    std::fs::write(vars_path, new_content).expect("Failed to write vars/default.nix");
}

struct Act {
    ty: u64,
    start: f64,
    stop: Option<f64>,
    name: String,
    bytes: u64,
}

fn union(mut iv: Vec<(f64, f64)>) -> f64 {
    iv.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let (mut total, mut end) = (0.0, f64::MIN);
    for (s, e) in iv {
        total += (e - s.max(end)).max(0.0);
        end = end.max(e);
    }
    total
}

fn human(b: u64) -> String {
    if b < 1 << 20 { format!("{:.1} KiB", b as f64 / 1024.0) } else { format!("{:.1} MiB", b as f64 / 1048576.0) }
}

fn bar(secs: f64, total: f64) -> String {
    let n = (secs / total * 40.0).round() as usize;
    format!("{}{}", "█".repeat(n), "·".repeat(40 - n))
}

// nixos-rebuild forwards unknown flags to `nix build`, so `--log-format internal-json` reaches it; its
// "building"/"activating" progress lines are the only phase markers outside the @nix stream.
fn run_timed(mut cmd: Command, show_build_logs: bool) -> std::process::ExitStatus {
    cmd.args(["--log-format", "internal-json"]).stderr(Stdio::piped());
    let t0 = Instant::now();
    let mut child = cmd.spawn().expect("Failed to run nixos-rebuild");
    let mut acts: HashMap<u64, Act> = HashMap::new();
    let (mut build_at, mut activate_at) = (None, None);
    let mut stderr = std::io::stderr().lock();
    for line in BufReader::new(child.stderr.take().unwrap()).lines() {
        let line = line.expect("stderr not utf-8");
        let t = t0.elapsed().as_secs_f64();
        let Some(json) = line.strip_prefix("@nix ") else {
            if line.starts_with("building the system configuration") {
                build_at = Some(t);
            } else if line.starts_with("activating the configuration") {
                activate_at = Some(t);
            }
            writeln!(stderr, "{line}").unwrap();
            continue;
        };
        let ev: Value = serde_json::from_str(json).unwrap_or_else(|e| panic!("bad nix event {json}: {e}"));
        let id = ev["id"].as_u64();
        let fields = &ev["fields"];
        match ev["action"].as_str().expect("event without action") {
            "start" => {
                let ty = ev["type"].as_u64().unwrap();
                let name = match ty {
                    105 => {
                        let drv = fields[0].as_str().unwrap().rsplit('/').next().unwrap();
                        drv.split_once('-').unwrap().1.trim_end_matches(".drv").to_string()
                    }
                    108 => fields[0].as_str().unwrap().rsplit('/').next().unwrap().to_string(),
                    _ => String::new(),
                };
                acts.insert(id.unwrap(), Act { ty, start: t, stop: None, name, bytes: 0 });
            }
            "stop" => {
                if let Some(a) = acts.get_mut(&id.unwrap()) {
                    a.stop = Some(t);
                }
            }
            "result" => match ev["type"].as_u64().unwrap() {
                105 => {
                    if let Some(a) = acts.get_mut(&id.unwrap()) {
                        a.bytes = a.bytes.max(fields[0].as_u64().unwrap());
                    }
                }
                101 if show_build_logs => writeln!(stderr, "{}", fields[0].as_str().unwrap()).unwrap(),
                _ => {}
            },
            "msg" => writeln!(stderr, "{}", ev["msg"].as_str().unwrap()).unwrap(),
            _ => {}
        }
    }
    let status = child.wait().unwrap();
    let total = t0.elapsed().as_secs_f64();

    let build_at = build_at.expect("no 'building the system configuration' line from nixos-rebuild");
    let activate_at = activate_at.unwrap_or(total);
    let iv = |ty: u64| -> Vec<(f64, f64)> {
        acts.values().filter(|a| a.ty == ty).map(|a| (a.start, a.stop.unwrap_or(activate_at))).collect()
    };
    let eval_end = acts.values().filter(|a| matches!(a.ty, 102 | 104 | 105 | 108)).map(|a| a.start).fold(activate_at, f64::min);
    let (subs, builds) = (iv(108), iv(105));
    let dl_bytes: u64 = acts.values().filter(|a| a.ty == 101).map(|a| a.bytes).sum();
    let phases = [
        ("eval", eval_end - build_at, String::new()),
        ("substitute", union(subs.clone()), format!("{} paths, {}", subs.len(), human(dl_bytes))),
        ("build", union(builds.clone()), format!("{} drvs", builds.len())),
        ("switch", total - activate_at, String::new()),
    ];
    let covered = union(vec![(build_at, eval_end), (activate_at, total)].into_iter().chain(subs).chain(builds).collect());
    let overlap = phases.iter().map(|p| p.1).sum::<f64>() - covered;

    eprintln!("\n== nb timings ==");
    for (name, secs, note) in &phases {
        eprintln!("{name:<11}{} {secs:>6.1}s  {note}", bar(*secs, total));
    }
    eprintln!("total {total:.1}s; phase overlap {overlap:.1}s; unattributed (realise checks, nix-env, wiring) {:.1}s", total - covered);
    let mut slow: Vec<&Act> = acts.values().filter(|a| a.ty == 105).collect();
    slow.sort_by(|a, b| (b.stop.unwrap_or(activate_at) - b.start).partial_cmp(&(a.stop.unwrap_or(activate_at) - a.start)).unwrap());
    if !slow.is_empty() {
        eprintln!("slowest local builds:");
        let max = slow[0].stop.unwrap_or(activate_at) - slow[0].start;
        for a in slow.iter().take(15) {
            let d = a.stop.unwrap_or(activate_at) - a.start;
            eprintln!("  {} {d:>6.1}s  {}", bar(d, max), a.name);
        }
    }
    status
}

fn main() {
    let args = Args::parse();

    if let Some(v) = args.sccache {
        set_nix_var("sccache", if v { "true" } else { "false" });
    }

    // Get hostname
    let hostname_output = Command::new("hostname")
        .output()
        .expect("Failed to get hostname");
    let hostname = String::from_utf8_lossy(&hostname_output.stdout)
        .trim()
        .to_string();

    // Build the command
    let mut cmd = Command::new("sudo");
    cmd.args(["nixos-rebuild", "switch", "--impure", "--no-reexec"]);
    cmd.arg("--flake");
    cmd.arg(format!("/home/v/nix#{hostname}"));

    // Add debug flags if requested
    if args.debug {
        cmd.args(["--show-trace", "--option", "abort-on-warn", "true"]);
    }

    // Add extra arguments
    if !args.extra_args.is_empty() {
        cmd.args(&args.extra_args);
    }

    let status = if args.timings {
        run_timed(cmd, args.extra_args.iter().any(|a| a == "-L" || a == "--print-build-logs"))
    } else {
        cmd.status().expect("Failed to run nixos-rebuild")
    };
    let status_code = status.code().unwrap_or(1);

    // Refresh shell init caches after successful rebuild
    if status.success() {
        eprintln!("Refreshing shell init caches...");
        let _ = Command::new("fish")
            .args(["-c", "refresh_shell_init_caches"])
            .status();
    }

    // Play final beep if requested
    if args.beep {
        let _ = Command::new("beep")
            .arg(format!("nix rb {status_code}"))
            .status();
    }

    std::process::exit(status_code);
}
