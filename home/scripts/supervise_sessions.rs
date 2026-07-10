#!/home/v/nix/home/scripts/nix-run-cached
---cargo
[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
---

use clap::Parser;
use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::process::Command;
use std::time::{Duration, Instant};

const CLAUDE_SESSIONS: &str = "/home/v/nix/home/config/tmux/claude_sessions.rs";
const SMART_SHUTDOWN: &str = "/home/v/nix/home/scripts/smart_shutdown.rs";
const POLL: Duration = Duration::from_secs(60);

/// Babysit the Claude sessions that are active right now: report each one as it
/// finishes, then shut the machine down once none are left (or the cutoff hits).
#[derive(Parser)]
#[command(name = "supervise_sessions")]
struct Args {
    /// Hard cutoff: if sessions are still active after this many minutes, assume
    /// something is stuck and shut down anyway.
    #[arg(long, default_value_t = 45)]
    timeout_m: u64,

    /// Report as usual but don't actually shut down.
    #[arg(short = 'n', long)]
    dry_run: bool,
}

#[derive(Deserialize)]
struct Entry {
    name: String,
    state: String,
}

fn active_now() -> HashSet<String> {
    let out = Command::new(CLAUDE_SESSIONS)
        .arg("--json")
        .output()
        .expect("claude_sessions must be runnable");
    if !out.status.success() {
        eprintln!("claude_sessions exited {}: {}", out.status, String::from_utf8_lossy(&out.stderr));
        std::process::exit(1);
    }
    let entries: Vec<Entry> = serde_json::from_slice(&out.stdout).expect("claude_sessions --json is valid JSON");
    entries.into_iter().filter(|e| e.state == "active").map(|e| e.name).collect()
}

// Best-effort: a failed notification must not block the shutdown, and the skill's
// watchdog notices a silent run. So we log and carry on rather than panic.
fn tg(msg: &str) {
    println!("{msg}");
    if let Err(e) = Command::new("tg").args(["send", "-c", "general", msg]).status() {
        eprintln!("tg send failed: {e}");
    }
}

fn shutdown(dry_run: bool) {
    if dry_run {
        println!("[dry-run] would shut down now");
        return;
    }
    let ok = Command::new(SMART_SHUTDOWN).status().map(|s| s.success()).unwrap_or(false);
    if !ok {
        eprintln!("smart_shutdown failed; falling back to `shutdown now`");
        Command::new("shutdown").arg("now").status().expect("shutdown must run");
    }
}

fn main() {
    let args = Args::parse();

    let watched = active_now();
    if watched.is_empty() {
        tg("supervise: no active sessions — shutting down");
        shutdown(args.dry_run);
        return;
    }

    let mut sorted: Vec<_> = watched.iter().cloned().collect();
    sorted.sort();
    tg(&format!("supervise: watching {} session(s): {}", watched.len(), sorted.join(", ")));

    let total = watched.len();
    let mut remaining = watched;
    // Require two consecutive non-active reads before declaring a session done, so a
    // momentary between-turns blip can't trigger an early shutdown.
    // ponytail: 2-read debounce; widen if false "finished" reports show up.
    let mut idle_streak: HashMap<String, u8> = HashMap::new();
    let start = Instant::now();
    let cutoff = Duration::from_secs(args.timeout_m * 60);

    loop {
        std::thread::sleep(POLL);

        if start.elapsed() >= cutoff {
            let mut still: Vec<_> = remaining.iter().cloned().collect();
            still.sort();
            tg(&format!("supervise: {}m cutoff hit, still active: {} — forcing shutdown", args.timeout_m, still.join(", ")));
            break;
        }

        let active = active_now();
        let done: Vec<String> = remaining
            .iter()
            .filter(|name| {
                if active.contains(*name) {
                    idle_streak.insert((*name).clone(), 0);
                    false
                } else {
                    let s = idle_streak.entry((*name).clone()).or_insert(0);
                    *s += 1;
                    *s >= 2
                }
            })
            .cloned()
            .collect();

        for name in done {
            remaining.remove(&name);
            idle_streak.remove(&name);
            tg(&format!("supervise: ✓ {name} finished ({}/{total})", total - remaining.len()));
        }

        if remaining.is_empty() {
            tg("supervise: all sessions done — shutting down");
            break;
        }
    }

    shutdown(args.dry_run);
}
