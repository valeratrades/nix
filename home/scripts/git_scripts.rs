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
    /// Create PR, merge it into target branch, and delete source branch
    Pr {
        /// Target branch to merge into (e.g., master, main)
        target_branch: Option<String>,
        /// Create a draft PR without merging
        #[arg(long)]
        draft: bool,
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

fn pr(target_branch: Option<String>, draft: bool) {
    // Check we're in a git repo
    if !run_cmd_quiet("git", &["rev-parse", "--is-inside-work-tree"]) {
        eprintln!("ERROR: Not in a git repository");
        std::process::exit(1);
    }

    let current_branch = match run_cmd_output("git", &["branch", "--show-current"]) {
        Some(b) if !b.is_empty() => b,
        _ => {
            eprintln!("ERROR: Could not get current branch");
            std::process::exit(1);
        }
    };

    // Draft mode: just create a draft PR and exit
    if draft {
        let mut args = vec!["pr", "create", "--draft", "--fill", "--head", &current_branch];
        let target = target_branch.as_deref();
        if let Some(t) = target {
            args.push("-B");
            args.push(t);
        }
        println!("Creating draft PR for branch '{}'", current_branch);
        let output = Command::new("gh")
            .args(&args)
            .output();
        match output {
            Ok(o) if o.status.success() => {}
            Ok(o) if String::from_utf8_lossy(&o.stderr).contains("already exists") => {
                println!("Draft PR already exists");
            }
            _ => {
                eprintln!("ERROR: Failed to create draft PR");
                std::process::exit(1);
            }
        }
        return;
    }

    let target_branch = match target_branch {
        Some(b) => b,
        None => {
            eprintln!("ERROR: target_branch is required when not using --draft");
            std::process::exit(1);
        }
    };

    if current_branch == target_branch {
        eprintln!("ERROR: Already on target branch '{}'", target_branch);
        std::process::exit(1);
    }

    println!("Creating PR: {} -> {}", current_branch, target_branch);

    // Try to create the PR (use --head to avoid push detection issues)
    let pr_create_output = Command::new("gh")
        .args([
            "pr", "create",
            "-B", &target_branch,
            "-f",
            "-t", &current_branch,
            "--head", &current_branch,
        ])
        .stdin(Stdio::null())
        .output();

    let pr_already_exists = match &pr_create_output {
        Ok(o) => String::from_utf8_lossy(&o.stderr).contains("already exists"),
        Err(_) => false,
    };

    if !pr_already_exists && !pr_create_output.map(|o| o.status.success()).unwrap_or(false) {
        eprintln!("ERROR: Failed to create PR");
        std::process::exit(1);
    }

    if pr_already_exists {
        println!("PR already exists, proceeding to merge...");
    }

    // Get PR number for the current branch (matches by head branch, not title)
    let pr_view_output = Command::new("gh")
        .args(["pr", "view", "--json", "number"])
        .output();

    let pr_number = match pr_view_output {
        Ok(output) if output.status.success() => {
            let json_str = String::from_utf8_lossy(&output.stdout);
            // Format: {"number":123}
            json_str
                .split("\"number\":")
                .nth(1)
                .and_then(|s| s.split(|c: char| !c.is_ascii_digit()).next())
                .filter(|s| !s.is_empty())
                .map(|s| s.to_string())
        }
        _ => None,
    };

    let pr_number = match pr_number {
        Some(n) => n,
        None => {
            eprintln!("ERROR: Could not find PR number for '{}'", current_branch);
            std::process::exit(1);
        }
    };

    println!("Merging PR #{}", pr_number);

    // Checkout target branch
    if !run_cmd("git", &["checkout", &target_branch]) {
        eprintln!("ERROR: Failed to checkout {}", target_branch);
        std::process::exit(1);
    }

    // Merge the PR with delete and merge commit
    let merge_status = Command::new("gh")
        .args(["pr", "merge", "-dm", &pr_number])
        .stdin(Stdio::null())
        .status();

    if !merge_status.map(|s| s.success()).unwrap_or(false) {
        eprintln!("ERROR: Failed to merge PR");
        std::process::exit(1);
    }

    // Pull to get the merge commit locally
    run_cmd("git", &["pull"]);

    println!("Successfully merged '{}' into '{}'", current_branch, target_branch);
}

fn main() {
    let args = Args::parse();

    match args.command {
        Commands::Fork { message } => fork(message),
        Commands::Pr { target_branch, draft } => pr(target_branch, draft),
    }
}
