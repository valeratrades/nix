#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::{Parser, Subcommand};
use std::env;
use std::process::{Command, Stdio};

#[derive(Parser, Debug)]
#[command(name = "git")]
#[command(about = "Git helper commands")]
struct Args {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Fork current repo and push changes to your fork
    Fork {
        /// Commit message (if provided, commits all changes first)
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        message: Vec<String>,
    },
}

fn run_cmd(cmd: &str, args: &[&str]) -> bool {
    Command::new(cmd)
        .args(args)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn run_cmd_output(cmd: &str, args: &[&str]) -> Option<String> {
    Command::new(cmd)
        .args(args)
        .stderr(Stdio::null())
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
}

fn run_cmd_quiet(cmd: &str, args: &[&str]) -> bool {
    Command::new(cmd)
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn run_gg(message: &[String]) {
    let gg_cmd = if message.is_empty() {
        "gg".to_string()
    } else {
        format!("gg {}", message.join(" "))
    };
    let status = Command::new("fish")
        .args(["-c", &gg_cmd])
        .status()
        .map(|s| s.code().unwrap_or(1))
        .unwrap_or(1);
    if status != 0 {
        std::process::exit(status);
    }
}

fn fork(message: Vec<String>) {
    // Check we're in a git repo
    if !run_cmd_quiet("git", &["rev-parse", "--is-inside-work-tree"]) {
        eprintln!("ERROR: Not in a git repository");
        std::process::exit(1);
    }

    let github_name = match env::var("GITHUB_NAME") {
        Ok(v) => v,
        Err(_) => {
            eprintln!("ERROR: GITHUB_NAME is not set");
            std::process::exit(1);
        }
    };

    let origin_url = match run_cmd_output("git", &["remote", "get-url", "origin"]) {
        Some(url) => url,
        None => {
            eprintln!("ERROR: No origin remote found");
            std::process::exit(1);
        }
    };

    // Check if origin already points to our repo
    if origin_url.contains(&format!("github.com/{}/", github_name))
        || origin_url.contains(&format!("github.com:{}/", github_name))
    {
        println!("Origin already points to your repo, running gg...");
        // Ensure branch tracks origin (might still track upstream from previous fork setup)
        if let Some(branch) = run_cmd_output("git", &["rev-parse", "--abbrev-ref", "HEAD"]) {
            let tracking = run_cmd_output("git", &["config", &format!("branch.{}.remote", branch)]);
            if tracking.as_deref() != Some("origin") {
                run_cmd("git", &["push", "-u", "origin", &branch]);
            }
        }
        run_gg(&message);
        return;
    }

    // Extract repo name: strip .git suffix, take everything after last /
    let repo_name = origin_url
        .trim_end_matches(".git")
        .rsplit('/')
        .next()
        .unwrap_or("");

    if repo_name.is_empty() {
        eprintln!("ERROR: Could not extract repo name from origin URL: {}", origin_url);
        std::process::exit(1);
    }

    println!("Forking repository...");
    // gh repo fork creates fork if needed, is idempotent
    let _ = Command::new("gh")
        .args(["repo", "fork", "--remote=false"])
        .stdout(Stdio::null())
        .status();

    // Setup remotes: upstream = original, origin = fork
    let fork_url = format!("https://github.com/{}/{}.git", github_name, repo_name);

    // Check if upstream already exists
    let has_upstream = run_cmd_quiet("git", &["remote", "get-url", "upstream"]);

    if has_upstream {
        // upstream exists, just update origin
        run_cmd("git", &["remote", "set-url", "origin", &fork_url]);
    } else {
        // Rename origin to upstream, add fork as origin
        run_cmd_quiet("git", &["remote", "rename", "origin", "upstream"]);
        if !run_cmd_quiet("git", &["remote", "add", "origin", &fork_url]) {
            run_cmd("git", &["remote", "set-url", "origin", &fork_url]);
        }
    }

    println!("Pushing to {} ...", fork_url);

    // Initial push to fork with -u to set up tracking (branch now tracks origin instead of upstream)
    if let Some(branch) = run_cmd_output("git", &["rev-parse", "--abbrev-ref", "HEAD"]) {
        if !run_cmd("git", &["push", "-u", "origin", &branch]) {
            eprintln!("ERROR: Failed to push to fork");
            std::process::exit(1);
        }
    }

    run_gg(&message);
}

fn main() {
    let args = Args::parse();

    match args.command {
        Commands::Fork { message } => fork(message),
    }
}
