#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::Parser;
use std::process::{Command, Stdio};

/// Smart shutdown with pre-shutdown cleanup
#[derive(Parser, Debug)]
#[command(name = "smart_shutdown")]
#[command(about = "Clean shutdown: terminates tmux, kills slow services, then shuts down")]
struct Args {
    /// Run claude_sessions and send to telegram before shutdown
    #[arg(short, long)]
    claude_sessions: bool,

    /// Skip the actual shutdown (dry run)
    #[arg(short = 'n', long)]
    dry_run: bool,
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

fn main() {
    let args = Args::parse();

    // 1. Run claude_sessions and send to telegram if requested
    if args.claude_sessions {
        println!("Saving claude sessions to telegram...");
        let claude_sessions_path = std::env::var("HOME")
            .map(|h| format!("{h}/nix/home/config/tmux/claude-sessions.rs"))
            .unwrap_or_else(|_| "/home/v/nix/home/config/tmux/claude-sessions.rs".to_string());

        let output = Command::new(&claude_sessions_path)
            .output();

        match output {
            Ok(out) if out.status.success() => {
                let sessions = String::from_utf8_lossy(&out.stdout);
                if !sessions.trim().is_empty() {
                    // Send to telegram
                    let tg_result = Command::new("tg")
                        .args(["send", "-c", "general", "-"])
                        .stdin(Stdio::piped())
                        .spawn()
                        .and_then(|mut child| {
                            use std::io::Write;
                            if let Some(ref mut stdin) = child.stdin {
                                stdin.write_all(sessions.as_bytes())?;
                            }
                            child.wait()
                        });

                    match tg_result {
                        Ok(status) if status.success() => println!("Claude sessions sent to telegram"),
                        Ok(_) => eprintln!("Warning: tg command failed"),
                        Err(e) => eprintln!("Warning: failed to run tg: {e}"),
                    }
                } else {
                    println!("No claude sessions to send");
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
    }

    // 2. Kill tmux sessions
    println!("Terminating tmux sessions...");
    run_cmd_silent("tmux", &["kill-server"]);

    // 3. Stop problematic services (these often hang on shutdown)
    println!("Stopping slow services...");

    // Stop user services that might hang
    // tailscaled is a system service, needs sudo
    run_cmd_silent("sudo", &["systemctl", "stop", "tailscaled"]);

    // clickhouse and postgresql are also system services
    run_cmd_silent("sudo", &["systemctl", "stop", "clickhouse"]);
    run_cmd_silent("sudo", &["systemctl", "stop", "postgresql"]);

    // 4. Shutdown
    if args.dry_run {
        println!("Dry run - would run: sudo shutdown now");
    } else {
        println!("Shutting down...");
        let status = Command::new("sudo")
            .args(["shutdown", "now"])
            .status();

        if let Err(e) = status {
            eprintln!("Failed to shutdown: {e}");
            std::process::exit(1);
        }
    }
}
