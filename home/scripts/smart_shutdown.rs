#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde_json = "1"
---

use clap::Parser;
use std::process::{Command, Stdio};

/// Smart shutdown with pre-shutdown cleanup
#[derive(Parser, Debug)]
#[command(name = "smart_shutdown")]
#[command(about = "Clean shutdown: terminates tmux, kills slow services, then shuts down")]
struct Args {
    /// Skip the actual shutdown (dry run)
    #[arg(short = 'n', long)]
    dry_run: bool,

    /// Internal flag: run as detached process (used when inside tmux)
    #[arg(long, hide = true)]
    detached: bool,
}

fn run_cmd_silent(cmd: &str, args: &[&str]) -> bool {
    Command::new(cmd)
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// `session_path\tcwd\tsession_id\tconfig_dir` per live tmux-hosted claude, consumed by fish's `restore_sessions` on boot.
fn write_claude_inventory(dry_run: bool) {
    let home = std::env::var("HOME").expect("HOME not set");
    let state_dir = std::env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{home}/.local/state"));
    let path = format!("{state_dir}/claude_restore.tsv");

    let out = match Command::new("tmux")
        .args(["list-panes", "-a", "-F", "#{pane_id}\t#{session_path}"])
        .output()
    {
        Ok(out) if out.status.success() => out,
        // No tmux server still records an empty layout, so the previous shutdown cannot linger.
        _ if dry_run => {
            println!("Dry run - no tmux panes; would save an empty inventory to {path}");
            return;
        }
        _ => {
            std::fs::write(&path, "").expect("failed to write empty claude inventory");
            println!("No tmux panes; saved empty inventory to {path}");
            return;
        }
    };
    let panes: Vec<(String, String)> = String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(|l| {
            let (id, p) = l.split_once('\t').expect("format string has a tab");
            (id.to_string(), p.to_string())
        })
        .collect();

    // claude keeps `<config_dir>/sessions/<pid>.json` for each live process; `--acc N` sessions live under ~/.claude-accountN
    let mut content = String::new();
    for entry in std::fs::read_dir(&home).expect("HOME unreadable") {
        let config_dir = entry.expect("HOME entry unreadable").path();
        let name = config_dir.file_name().unwrap().to_string_lossy().into_owned();
        if name != ".claude" && !name.starts_with(".claude-account") {
            continue;
        }
        let Ok(sessions) = std::fs::read_dir(config_dir.join("sessions")) else {
            continue; // account never ran an interactive session
        };
        for f in sessions {
            let f = f.expect("sessions entry unreadable").path();
            if f.extension().is_none_or(|e| e != "json") {
                continue;
            }
            let raw = std::fs::read_to_string(&f).expect("session file unreadable");
            let j: serde_json::Value = serde_json::from_str(&raw).unwrap_or_else(|e| panic!("{}: {e}", f.display()));
            let pid = j["pid"].as_u64().unwrap_or_else(|| panic!("{}: no pid", f.display()));
            if !std::path::Path::new(&format!("/proc/{pid}")).exists() {
                continue; // left behind by a crashed claude
            }
            let Some(tmux) = j["tmux"].as_str() else {
                continue; // not launched inside tmux, nothing to rebuild it into
            };
            let pane_id = tmux.rsplit_once('.').unwrap_or_else(|| panic!("{}: unexpected tmux field '{tmux}'", f.display())).1;
            let Some((_, session_path)) = panes.iter().find(|(id, _)| id == pane_id) else {
                continue; // claude on another tmux server
            };
            let cwd = j["cwd"].as_str().unwrap_or_else(|| panic!("{}: no cwd", f.display()));
            let id = j["sessionId"].as_str().unwrap_or_else(|| panic!("{}: no sessionId", f.display()));
            content.push_str(&format!("{session_path}\t{cwd}\t{id}\t{}\n", config_dir.display()));
        }
    }

    let n = content.lines().count();
    if dry_run {
        println!("Dry run - would record {n} claude(s) to {path}:\n{content}");
        return;
    }
    std::fs::write(&path, &content).expect("failed to write claude inventory");
    println!("Recorded {n} claude(s) to {path}");
}

fn main() {
    let args = Args::parse();

    // Spawned from the tg gateway (via supervise_sessions) we inherit a PATH without the
    // user profile, where tg/tedi/tmux don't resolve and every step below fails silently.
    // Safe here: no threads spawned yet.
    unsafe {
        let path = std::env::var("PATH").unwrap_or_default();
        std::env::set_var("PATH", format!("/etc/profiles/per-user/v/bin:{path}"));
    }

    // If we're inside tmux and not already detached, re-exec ourselves detached from tmux
    if !args.detached && std::env::var("TMUX").is_ok() {
        let exe = std::env::current_exe().expect("Failed to get current executable path");
        let mut cmd_args = vec!["--detached".to_string()];
        if args.dry_run {
            cmd_args.push("--dry-run".to_string());
        }

        // Use setsid to create a new session, detaching from the terminal
        let status = Command::new("setsid")
            .arg("--fork")
            .arg(&exe)
            .args(&cmd_args)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();

        match status {
            Ok(s) if s.success() => {
                println!("Shutdown process started in background");
                std::process::exit(0);
            }
            Ok(s) => {
                eprintln!("Failed to start detached process: exit code {:?}", s.code());
                std::process::exit(1);
            }
            Err(e) => {
                eprintln!("Failed to start detached process: {e}");
                std::process::exit(1);
            }
        }
    }

    // 1. Pre-shutdown async tasks: claude_sessions->tg and tedi tracking halt
    let dry_run = args.dry_run;
    let tedi_handle = std::thread::spawn(move || {
        if dry_run {
            println!("Dry run - would halt tedi tracking");
            return;
        }
        println!("Halting tedi tracking...");
        match Command::new("tedi")
            .args(["-y", "sprints", "selected", "halt"])
            .status()
        {
            Ok(s) if s.success() => println!("tedi tracking halted"),
            Ok(_) => eprintln!("Warning: tedi halt failed"),
            Err(e) => eprintln!("Warning: failed to run tedi: {e}"),
        }
    });

    let claude_handle = std::thread::spawn(move || {
        if dry_run {
            println!("Dry run - would send claude sessions to telegram");
            return;
        }
        println!("Saving claude sessions to telegram...");
        let claude_sessions_path = std::env::var("HOME")
            .map(|h| format!("{h}/nix/home/config/tmux/claude_sessions.rs"))
            .unwrap_or_else(|_| "/home/v/nix/home/config/tmux/claude_sessions.rs".to_string());

        let output = Command::new(&claude_sessions_path).output();

        match output {
            Ok(out) if out.status.success() => {
                let sessions = String::from_utf8_lossy(&out.stdout);
                let msg = if sessions.trim().is_empty() {
                    eprintln!("Warning: claude_sessions output empty");
                    "warning: claude_sessions output was empty"
                } else {
                    sessions.as_ref()
                };
                // Pass the whole output as a positional argument, NOT via stdin `-`.
                // The `-` stdin path in `tg send` truncates multi-line input to its
                // last line; a positional arg preserves every line.
                let tg_result = Command::new("tg")
                    .args(["send", "-c", "general", msg])
                    .status();

                match tg_result {
                    Ok(status) if status.success() => println!("Claude sessions sent to telegram"),
                    Ok(_) => eprintln!("Warning: tg command failed"),
                    Err(e) => eprintln!("Warning: failed to run tg: {e}"),
                }
            }
            Ok(out) => {
                let stderr = String::from_utf8_lossy(&out.stderr);
                eprintln!("Warning: claude_sessions failed: {stderr}");
            }
            Err(e) => {
                eprintln!("Warning: failed to run claude_sessions: {e}");
            }
        }
    });

    // Must run while the tmux server is still alive (see the kill-server below).
    let dry_run = args.dry_run;
    let inventory_handle = std::thread::spawn(move || write_claude_inventory(dry_run));

    // Wait for all three to finish before proceeding with shutdown
    tedi_handle.join().expect("tedi thread panicked");
    claude_handle.join().expect("claude_sessions thread panicked");
    inventory_handle.join().expect("inventory thread panicked");

    // 2. Kill tmux sessions
    if args.dry_run {
        println!("Dry run - would kill the tmux server and stop tailscaled/clickhouse/postgresql");
    } else {
        println!("Terminating tmux sessions...");
        run_cmd_silent("tmux", &["kill-server"]);

        // 3. Stop problematic services (these often hang on shutdown)
        println!("Stopping slow services...");

        // tailscaled is a system service, needs sudo
        run_cmd_silent("sudo", &["systemctl", "stop", "tailscaled"]);

        // clickhouse has a known slow shutdown bug in 25.x (~39s delay)
        // Just kill it - data is trivial and not worth waiting for
        run_cmd_silent("sudo", &["pkill", "-9", "clickhouse"]);

        // postgresql if it's running
        run_cmd_silent("sudo", &["systemctl", "stop", "postgresql"]);
    }

    // 4. Shutdown. `shutdown now` is the ambiguous compat interface (halt vs
    // poweroff) — use systemctl poweroff, and treat a non-zero exit as failure so
    // callers can't mistake "poweroff refused" for success.
    if args.dry_run {
        println!("Dry run - would run: sudo systemctl poweroff");
    } else {
        println!("Shutting down...");
        match Command::new("sudo").args(["systemctl", "poweroff"]).status() {
            Ok(s) if s.success() => {}
            Ok(s) => {
                eprintln!("poweroff exited with {:?}", s.code());
                std::process::exit(1);
            }
            Err(e) => {
                eprintln!("Failed to power off: {e}");
                std::process::exit(1);
            }
        }
    }
}
