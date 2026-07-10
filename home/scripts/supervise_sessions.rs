#!/home/v/nix/home/scripts/nix-run-cached
---cargo
[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
---

use clap::Parser;
use serde::Deserialize;
use std::collections::{BTreeSet, HashMap};
use std::process::Command;
use std::time::Duration;

const CLAUDE_SESSIONS: &str = "/home/v/nix/home/config/tmux/claude_sessions.rs";
const SMART_SHUTDOWN: &str = "/home/v/nix/home/scripts/smart_shutdown.rs";
const TG: &str = "/etc/profiles/per-user/v/bin/tg"; // gateway PATH lacks the user profile; call it explicitly
const POLL: Duration = Duration::from_secs(60);

/// Babysit the Claude sessions that are active right now: report each one as it
/// settles, then shut the machine down once none are left. A horizon on the main
/// thread guarantees shutdown even if session polling is broken or hangs.
#[derive(Parser)]
#[command(name = "supervise_sessions")]
struct Args {
    /// Termination horizon: shut down this many minutes after start no matter what
    /// (even if session polling is broken or hangs). Early shutdown still happens
    /// as soon as all sessions settle.
    #[arg(long, default_value_t = 45)]
    timeout_m: u64,

    /// Consecutive idle reads (~1min apart) before a session that merely *looks* idle
    /// (finished/empty/error) is concluded done. Deterministic states (question, limit)
    /// settle on the first read regardless.
    #[arg(long, default_value_t = 3)]
    idle_reads: u8,

    /// Report as usual but don't actually shut down.
    #[arg(short = 'n', long)]
    dry_run: bool,
}

#[derive(Deserialize)]
struct Entry {
    name: String,
    state: String,
}

// Non-fatal: claude_sessions may be broken/hung. Any failure returns None so the
// caller keeps waiting for the horizon instead of dying here.
fn snapshot() -> Option<HashMap<String, String>> {
    let out = Command::new(CLAUDE_SESSIONS).arg("--json").output().ok()?;
    if !out.status.success() {
        eprintln!("claude_sessions exited {}: {}", out.status, String::from_utf8_lossy(&out.stderr));
        return None;
    }
    let entries: Vec<Entry> = serde_json::from_slice(&out.stdout).ok()?;
    Some(entries.into_iter().map(|e| (e.name, e.state)).collect())
}

// Best-effort: a failed notification must not block the shutdown.
fn tg(msg: &str) {
    println!("{msg}");
    if let Err(e) = Command::new(TG).args(["send", "-c", "general", msg]).status() {
        eprintln!("tg send failed: {e}");
    }
}

// smart_shutdown's exit status can't be trusted (it may report success while its
// poweroff never happens), so we ignore it: if control ever returns here we are
// still alive and force an unambiguous poweroff ourselves.
fn shutdown(dry_run: bool) {
    if dry_run {
        println!("[dry-run] would shut down now");
        return;
    }
    if let Err(e) = Command::new(SMART_SHUTDOWN).status() {
        eprintln!("smart_shutdown failed to spawn: {e}");
    }
    std::thread::sleep(Duration::from_secs(20)); // give smart_shutdown's cleanup a chance to take us down first
    if let Err(e) = Command::new("sudo").args(["systemctl", "poweroff"]).status() {
        eprintln!("`sudo systemctl poweroff` failed: {e}");
    }
}

// Runs on a background thread: shut down early once every initially-active session
// settles. Exits the process on shutdown; a broken snapshot just returns, leaving
// the main-thread horizon to handle it.
fn poll_until_settled(idle_reads: u8, dry_run: bool) {
    let Some(initial) = snapshot() else {
        tg("supervise: can't read sessions — deferring to horizon");
        return;
    };
    let watched: BTreeSet<String> = initial.into_iter().filter(|(_, s)| s == "active").map(|(n, _)| n).collect();
    if watched.is_empty() {
        tg("supervise: no active sessions — shutting down");
        shutdown(dry_run);
        std::process::exit(0);
    }
    tg(&format!("supervise: watching {} session(s): {}", watched.len(), watched.iter().cloned().collect::<Vec<_>>().join(", ")));

    let total = watched.len();
    let mut remaining = watched;
    let mut idle_streak: HashMap<String, u8> = HashMap::new();

    loop {
        std::thread::sleep(POLL);

        let Some(snap) = snapshot() else { continue }; // transient failure: retry; horizon still guaranteed

        let settled: Vec<(String, String)> = remaining
            .iter()
            .filter_map(|name| {
                // A session gone from the snapshot (window closed) settles as "gone".
                let state = snap.get(name).map(String::as_str).unwrap_or("gone");
                match state {
                    "active" => {
                        idle_streak.insert(name.clone(), 0);
                        None
                    }
                    // Deterministic: the session is blocked and won't resume on its own.
                    "question" | "limit" => Some((name.clone(), state.to_string())),
                    // Only *looks* idle — finished/empty/error can flip back to active
                    // between tool calls, so require enough consecutive idle reads first.
                    _ => {
                        let s = idle_streak.entry(name.clone()).or_insert(0);
                        *s += 1;
                        (*s >= idle_reads).then(|| (name.clone(), state.to_string()))
                    }
                }
            })
            .collect();

        for (name, state) in settled {
            remaining.remove(&name);
            idle_streak.remove(&name);
            let k = total - remaining.len();
            if state == "finished" {
                tg(&format!("supervise: ✓ {name} finished ({k}/{total})"));
            } else {
                tg(&format!("supervise: ⚠ {name} → {state} ({k}/{total})"));
            }
        }

        if remaining.is_empty() {
            tg("supervise: all sessions settled — shutting down");
            shutdown(dry_run);
            std::process::exit(0);
        }
    }
}

fn main() {
    let args = Args::parse();
    let horizon = Duration::from_secs(args.timeout_m * 60);

    std::thread::spawn(move || poll_until_settled(args.idle_reads, args.dry_run));

    // The main thread IS the termination horizon: a pure sleep nothing can block.
    std::thread::sleep(horizon);
    tg(&format!("supervise: {}m horizon reached — shutting down", args.timeout_m));
    shutdown(args.dry_run);
}
