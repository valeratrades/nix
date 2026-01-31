#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde_json = "1"
---

use clap::{Parser, Subcommand};
use std::env;
use std::fmt;
use std::process::{Command, ExitStatus, Stdio};

#[derive(Debug)]
struct GitError {
    cmd: String,
    args: Vec<String>,
    stderr: Option<String>,
    status: Option<ExitStatus>,
}

impl fmt::Display for GitError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} {} failed", self.cmd, self.args.join(" "))?;
        if let Some(status) = self.status {
            write!(f, " (exit: {})", status)?;
        }
        if let Some(ref stderr) = self.stderr {
            if !stderr.is_empty() {
                write!(f, ": {}", stderr)?;
            }
        }
        Ok(())
    }
}

type GitResult<T> = Result<T, GitError>;

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
    /// Push with optional force flags (refuses force on main branches unless harmless: renames or squashes)
    Push {
        /// Use --force-with-lease (safer force push)
        #[arg(long, short = 'l', conflicts_with = "force")]
        force_with_lease: bool,
        /// Use --force (dangerous, overwrites remote unconditionally)
        #[arg(long, short, conflicts_with = "force_with_lease")]
        force: bool,
        /// Additional arguments to pass to git push
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
    /// Delete a branch locally and on remote (refuses on main branches)
    Delete {
        /// Branch name to delete
        branch: String,
    },
    /// Create a new GitHub repository with standard labels and milestones
    Publish {
        /// Repository name (defaults to current directory name)
        repo_name: Option<String>,
        /// Create a private repository
        #[arg(long, conflicts_with = "public")]
        private: bool,
        /// Create a public repository
        #[arg(long, conflicts_with = "private")]
        public: bool,
        /// Commit all changes first with this message
        #[arg(short, long)]
        commit: Option<String>,
    },
}

/// Run command with inherited stdio (user sees output)
fn run_cmd(cmd: &str, args: &[&str]) -> GitResult<()> {
    let status = Command::new(cmd)
        .args(args)
        .status()
        .map_err(|e| GitError {
            cmd: cmd.to_string(),
            args: args.iter().map(|s| s.to_string()).collect(),
            stderr: Some(e.to_string()),
            status: None,
        })?;
    if status.success() {
        Ok(())
    } else {
        Err(GitError {
            cmd: cmd.to_string(),
            args: args.iter().map(|s| s.to_string()).collect(),
            stderr: None,
            status: Some(status),
        })
    }
}

/// Run command and capture stdout, suppressing stderr
fn run_cmd_output(cmd: &str, args: &[&str]) -> GitResult<String> {
    let output = Command::new(cmd)
        .args(args)
        .stderr(Stdio::piped())
        .output()
        .map_err(|e| GitError {
            cmd: cmd.to_string(),
            args: args.iter().map(|s| s.to_string()).collect(),
            stderr: Some(e.to_string()),
            status: None,
        })?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        Err(GitError {
            cmd: cmd.to_string(),
            args: args.iter().map(|s| s.to_string()).collect(),
            stderr: Some(String::from_utf8_lossy(&output.stderr).trim().to_string()),
            status: Some(output.status),
        })
    }
}

/// Run command silently, returns Ok(true) if success, Ok(false) if failed with exit code, Err if couldn't run
fn run_cmd_status(cmd: &str, args: &[&str]) -> GitResult<bool> {
    let status = Command::new(cmd)
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|e| GitError {
            cmd: cmd.to_string(),
            args: args.iter().map(|s| s.to_string()).collect(),
            stderr: Some(e.to_string()),
            status: None,
        })?;
    Ok(status.success())
}

fn run_gg(message: &[String]) {
    let gg_cmd = if message.is_empty() {
        "gg".to_string()
    } else {
        let msg = message.join(" ");
        format!("gg {msg}")
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
    if run_cmd_status("git", &["rev-parse", "--is-inside-work-tree"]).unwrap_or(false) != true {
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
        Ok(url) => url,
        Err(_) => {
            eprintln!("ERROR: No origin remote found");
            std::process::exit(1);
        }
    };

    // Check if origin already points to our repo
    if origin_url.contains(&format!("github.com/{github_name}/"))
        || origin_url.contains(&format!("github.com:{github_name}/"))
    {
        println!("Origin already points to your repo, running gg...");
        // Ensure branch tracks origin (might still track upstream from previous fork setup)
        if let Ok(branch) = run_cmd_output("git", &["rev-parse", "--abbrev-ref", "HEAD"]) {
            let tracking = run_cmd_output("git", &["config", &format!("branch.{branch}.remote")]).ok();
            if tracking.as_deref() != Some("origin") {
                let _ = run_cmd("git", &["push", "-u", "origin", &branch]);
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
        eprintln!("ERROR: Could not extract repo name from origin URL: {origin_url}");
        std::process::exit(1);
    }

    println!("Forking repository...");
    // gh repo fork creates fork if needed, is idempotent
    let _ = Command::new("gh")
        .args(["repo", "fork", "--remote=false"])
        .stdout(Stdio::null())
        .status();

    // Setup remotes: upstream = original, origin = fork
    let fork_url = format!("https://github.com/{github_name}/{repo_name}.git");

    // Check if upstream already exists
    let has_upstream = run_cmd_status("git", &["remote", "get-url", "upstream"]).unwrap_or(false);

    if has_upstream {
        // upstream exists, just update origin
        let _ = run_cmd("git", &["remote", "set-url", "origin", &fork_url]);
    } else {
        // Rename origin to upstream, add fork as origin
        let _ = run_cmd_status("git", &["remote", "rename", "origin", "upstream"]);
        if run_cmd_status("git", &["remote", "add", "origin", &fork_url]).unwrap_or(false) != true {
            let _ = run_cmd("git", &["remote", "set-url", "origin", &fork_url]);
        }
    }

    println!("Pushing to {fork_url} ...");

    // Initial push to fork with -u to set up tracking (branch now tracks origin instead of upstream)
    if let Ok(branch) = run_cmd_output("git", &["rev-parse", "--abbrev-ref", "HEAD"]) {
        if run_cmd("git", &["push", "-u", "origin", &branch]).is_err() {
            eprintln!("ERROR: Failed to push to fork");
            std::process::exit(1);
        }
    }

    run_gg(&message);
}

fn get_default_branch() -> Option<String> {
    // Try to get the default branch from GitHub via gh CLI
    run_cmd_output("gh", &["repo", "view", "--json", "defaultBranchRef", "-q", ".defaultBranchRef.name"]).ok()
}

fn pr(target_branch: Option<String>, draft: bool) {
    // Check we're in a git repo
    if run_cmd_status("git", &["rev-parse", "--is-inside-work-tree"]).unwrap_or(false) != true {
        eprintln!("ERROR: Not in a git repository");
        std::process::exit(1);
    }

    let current_branch = match run_cmd_output("git", &["branch", "--show-current"]) {
        Ok(b) if !b.is_empty() => b,
        _ => {
            eprintln!("ERROR: Could not get current branch");
            std::process::exit(1);
        }
    };

    // Resolve target branch: use provided value, or detect default branch
    let target_branch = match target_branch {
        Some(b) => b,
        None => match get_default_branch() {
            Some(b) => {
                println!("Using default branch: {b}");
                b
            }
            None => {
                eprintln!("ERROR: Could not detect default branch. Please specify target branch.");
                std::process::exit(1);
            }
        },
    };

    // Draft mode: just create a draft PR and exit
    if draft {
        let args = vec![
            "pr",
            "create",
            "--draft",
            "--fill",
            "--head",
            &current_branch,
            "-B",
            &target_branch,
        ];
        println!("Creating draft PR for branch '{current_branch}' -> '{target_branch}'");
        let output = Command::new("gh").args(args).output();
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

    if current_branch == target_branch {
        eprintln!("ERROR: Already on target branch '{target_branch}'");
        std::process::exit(1);
    }

    // Check if a PR already exists for this branch
    let existing_pr = Command::new("gh")
        .args(["pr", "view", "--json", "number,isDraft,baseRefName"])
        .output();

    let (pr_exists, is_draft, existing_base) = match &existing_pr {
        Ok(o) if o.status.success() => {
            let json_str = String::from_utf8_lossy(&o.stdout);
            let is_draft = json_str.contains("\"isDraft\":true");
            let base = json_str
                .split("\"baseRefName\":\"")
                .nth(1)
                .and_then(|s| s.split('"').next())
                .map(|s| s.to_string());
            (true, is_draft, base)
        }
        _ => (false, false, None),
    };

    if pr_exists {
        // Check if existing PR targets same branch
        if existing_base.as_deref() != Some(&target_branch) {
            eprintln!(
                "ERROR: Existing PR targets '{}', but you specified '{target_branch}'",
                existing_base.as_deref().unwrap_or("unknown")
            );
            std::process::exit(1);
        }

        if is_draft {
            println!("Found existing draft PR, marking ready for review...");
            if run_cmd("gh", &["pr", "ready"]).is_err() {
                eprintln!("ERROR: Failed to mark PR as ready");
                std::process::exit(1);
            }
        } else {
            println!("PR already exists, proceeding to merge...");
        }
    } else {
        println!("Creating PR: {current_branch} -> {target_branch}");

        // Try to create the PR (use --head to avoid push detection issues)
        let pr_create_output = Command::new("gh")
            .args([
                "pr",
                "create",
                "-B",
                &target_branch,
                "-f",
                "-t",
                &current_branch,
                "--head",
                &current_branch,
            ])
            .stdin(Stdio::null())
            .output();

        if !pr_create_output
            .map(|o| o.status.success())
            .unwrap_or(false)
        {
            eprintln!("ERROR: Failed to create PR");
            std::process::exit(1);
        }
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
            eprintln!("ERROR: Could not find PR number for '{current_branch}'");
            std::process::exit(1);
        }
    };

    println!("Merging PR #{pr_number}");

    // Checkout target branch
    if run_cmd("git", &["checkout", &target_branch]).is_err() {
        eprintln!("ERROR: Failed to checkout {target_branch}");
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
    let _ = run_cmd("git", &["pull"]);

    println!("Successfully merged '{current_branch}' into '{target_branch}'");
}

const GIT_SHARED_MAIN_BRANCHES: &[&str] = &["master", "main", "release", "stg", "prod"];

fn is_main_branch(branch: &str) -> bool {
    GIT_SHARED_MAIN_BRANCHES.contains(&branch)
}

fn push(force_with_lease: bool, force: bool, extra_args: Vec<String>) {
    if run_cmd_status("git", &["rev-parse", "--is-inside-work-tree"]).unwrap_or(false) != true {
        eprintln!("ERROR: Not in a git repository");
        std::process::exit(1);
    }

    let branch = match run_cmd_output("git", &["rev-parse", "--abbrev-ref", "HEAD"]) {
        Ok(b) if !b.is_empty() => b,
        _ => {
            eprintln!("ERROR: Could not get current branch");
            std::process::exit(1);
        }
    };

    // Fetch the remote branch to ensure we have up-to-date refs for comparison
    if let Err(e) = run_cmd_output("git", &["fetch", "origin", &format!("{branch}:refs/remotes/origin/{branch}")]) {
        eprintln!("ERROR: Failed to fetch origin/{branch}: {e}");
        std::process::exit(1);
    }
    // Store the fetched remote commit for --force-with-lease (avoids "stale info" error)
    let remote_ref = run_cmd_output("git", &["rev-parse", &format!("origin/{branch}")]).ok();

    let use_force = force;
    let mut use_force_with_lease = force_with_lease;
    let explicit_force = force_with_lease || force;

    // Check if we need a force push and whether it's safe
    let local_tree = run_cmd_output("git", &["rev-parse", "HEAD^{tree}"]).ok();
    let remote_tree = run_cmd_output("git", &["rev-parse", &format!("origin/{branch}^{{tree}}")]).ok();
    let remote_is_ancestor = run_cmd_status("git", &["merge-base", "--is-ancestor", &format!("origin/{branch}"), "HEAD"]).unwrap_or(false);
    let local_is_ancestor = run_cmd_status("git", &["merge-base", "--is-ancestor", "HEAD", &format!("origin/{branch}")]).unwrap_or(false);

    // Determine if force push would be safe
    let trees_match = matches!((&local_tree, &remote_tree), (Some(local), Some(remote)) if local == remote);

    // Check if we actually need a force push (histories diverged)
    let needs_force = !local_is_ancestor && !remote_is_ancestor;

    // Check if local contains remote's content
    // Safe scenarios:
    // 1. Remote tree appears in local history (exact match)
    // 2. Remote is merge-base with local (squash case: remote commits were squashed into local)
    // 3. No diff between local and remote (same content, different history)
    let local_contains_remote_content = needs_force && {
        // Check 1: exact tree match in history
        let tree_in_history = if let Some(ref r_tree) = remote_tree {
            run_cmd_output("git", &["log", "--format=%T", "HEAD"])
                .map(|trees| trees.lines().any(|t| t == r_tree))
                .unwrap_or(false)
        } else {
            false
        };

        // Check 2: remote is the merge-base (means local is a rewrite/squash of remote)
        let remote_is_merge_base = run_cmd_output("git", &["merge-base", "HEAD", &format!("origin/{branch}")])
            .map(|mb| run_cmd_output("git", &["rev-parse", &format!("origin/{branch}")]).ok().as_ref() == Some(&mb))
            .unwrap_or(false);

        // Check 3: no actual content difference (just history rewrite)
        let no_content_diff = run_cmd_output("git", &["diff", &format!("origin/{branch}"), "HEAD"])
            .map(|d| d.is_empty())
            .unwrap_or(false);

        tree_in_history || remote_is_merge_base || no_content_diff
    };

    if explicit_force && is_main_branch(&branch) {
        // User explicitly requested force - check if it's safe on main branches
        if trees_match || remote_is_ancestor || local_contains_remote_content {
            println!("Safe force push on {branch}: local contains all remote content.");
        } else {
            eprintln!("Refusing to force push {branch} (would lose remote content not in local)");
            std::process::exit(1);
        }
    } else if !explicit_force && needs_force {
        // No explicit force flag, but histories diverged - auto-force if safe
        if trees_match || local_contains_remote_content {
            println!("Local contains all remote content - auto-enabling force-with-lease.");
            use_force_with_lease = true;
        }
        // If not safe, let git push fail naturally with its error message
    }

    let extra_refs: Vec<&str> = extra_args.iter().map(|s| s.as_str()).collect();

    let mut args = vec!["push"];
    let force_with_lease_arg;
    if use_force {
        args.push("--force");
    } else if use_force_with_lease {
        // Use explicit expected value to avoid "stale info" error after fetch
        if let Some(ref expected) = remote_ref {
            force_with_lease_arg = format!("--force-with-lease=refs/heads/{branch}:{expected}");
            args.push(&force_with_lease_arg);
        } else {
            args.push("--force-with-lease");
        }
    }
    args.push("--follow-tags");
    args.extend(extra_refs);

    if run_cmd("git", &args).is_err() {
        std::process::exit(1);
    }
}

fn delete(branch: String) {
    if run_cmd_status("git", &["rev-parse", "--is-inside-work-tree"]).unwrap_or(false) != true {
        eprintln!("ERROR: Not in a git repository");
        std::process::exit(1);
    }

    if is_main_branch(&branch) {
        eprintln!("Refusing to delete {branch}");
        std::process::exit(1);
    }

    // Delete local branch
    if run_cmd("git", &["branch", "-D", &branch]).is_err() {
        eprintln!("ERROR: Failed to delete local branch {branch}");
        std::process::exit(1);
    }

    // Delete remote branch
    if run_cmd("git", &["push", "origin", "--delete", &branch]).is_err() {
        eprintln!("ERROR: Failed to delete remote branch {branch}");
        std::process::exit(1);
    }

    println!("Deleted branch {branch} locally and on remote");
}

struct Milestone {
    title: &'static str,
    description: &'static str,
}

const MILESTONES: &[Milestone] = &[
    Milestone { title: "1.0", description: "Minimum viable product" },
    Milestone { title: "2.0", description: "Fix bugs, rewrite hacks" },
    Milestone { title: "3.0", description: "More and better" },
];

fn create_milestone(github_name: &str, github_key: &str, repo_name: &str, milestone: &Milestone) {
    let title = milestone.title;
    let body = serde_json::json!({
        "title": title,
        "state": "open",
        "description": milestone.description
    });

    let output = Command::new("curl")
        .args([
            "-L", "-X", "POST",
            "-H", "Accept: application/vnd.github+json",
            "-H", &format!("Authorization: token {github_key}"),
            "-H", "X-GitHub-Api-Version: 2022-11-28",
            &format!("https://api.github.com/repos/{github_name}/{repo_name}/milestones"),
            "-d", &body.to_string(),
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();

    match output {
        Ok(s) if s.success() => println!("Created milestone '{title}'"),
        _ => eprintln!("Failed to create milestone '{title}'"),
    }
}

fn publish(repo_name: Option<String>, private: bool, public: bool, commit: Option<String>) {
    // Get environment variables
    let github_name = match env::var("GITHUB_NAME") {
        Ok(v) => v,
        Err(_) => {
            eprintln!("ERROR: GITHUB_NAME is not set");
            std::process::exit(1);
        }
    };

    let github_key = match env::var("GITHUB_KEY") {
        Ok(v) => v,
        Err(_) => {
            eprintln!("ERROR: GITHUB_KEY is not set");
            std::process::exit(1);
        }
    };

    let github_loc_gist = env::var("GITHUB_LOC_GIST").ok();
    if github_loc_gist.is_none() {
        eprintln!("WARNING: GITHUB_LOC_GIST is not set, loc_gist_token secret will not be created // in my setup it's used for LoC badge generation");
    }

    // Determine repo name
    let repo_name = repo_name.unwrap_or_else(|| {
        env::current_dir()
            .ok()
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
            .unwrap_or_else(|| {
                eprintln!("ERROR: Could not determine repository name");
                std::process::exit(1);
            })
    });

    // Determine visibility flag
    let visibility = if private {
        "--private"
    } else if public {
        "--public"
    } else {
        "--private" // default to private
    };

    println!("Creating repository: {repo_name}");

    // git init
    if run_cmd("git", &["init"]).is_err() {
        eprintln!("ERROR: git init failed");
        std::process::exit(1);
    }

    // git add . and commit
    if run_cmd("git", &["add", "."]).is_err() {
        eprintln!("ERROR: git add failed");
        std::process::exit(1);
    }

    let commit_msg = commit.as_deref().unwrap_or("Initial Commit");
    // Commit may fail if working tree is clean - that's okay, just continue
    let commit_output = Command::new("git")
        .args(["commit", "-m", commit_msg])
        .output();

    let commit_failed_fatally = match &commit_output {
        Ok(o) => {
            // Check if failure is due to "nothing to commit" - that's fine
            let stderr = String::from_utf8_lossy(&o.stderr);
            let stdout = String::from_utf8_lossy(&o.stdout);
            !o.status.success()
                && !stderr.contains("nothing to commit")
                && !stdout.contains("nothing to commit")
        }
        Err(_) => true,
    };

    if commit_failed_fatally {
        eprintln!("ERROR: git commit failed");
        std::process::exit(1);
    }

    // gh repo create
    if run_cmd("gh", &["repo", "create", &repo_name, visibility, "--source=."]).is_err() {
        eprintln!("ERROR: gh repo create failed");
        std::process::exit(1);
    }

    // git remote add origin
    let remote_url = format!("https://github.com/{github_name}/{repo_name}.git");
    // Remove existing origin if any, then add
    let _ = run_cmd_status("git", &["remote", "remove", "origin"]);
    if run_cmd("git", &["remote", "add", "origin", &remote_url]).is_err() {
        eprintln!("ERROR: git remote add failed");
        std::process::exit(1);
    }

    // git push
    if run_cmd("git", &["push", "-u", "origin", "master"]).is_err() {
        eprintln!("ERROR: git push failed");
        std::process::exit(1);
    }

    // Create milestones
    println!("\nCreating milestones...");
    for milestone in MILESTONES {
        create_milestone(&github_name, &github_key, &repo_name, milestone);
    }

    // Set loc_gist_token secret if available
    if let Some(loc_gist) = github_loc_gist {
        println!("\nSetting loc_gist_token secret...");
        let full_repo = format!("{github_name}/{repo_name}");
        if run_cmd("gh", &["secret", "set", "loc_gist_token", "--repo", &full_repo, "--body", &loc_gist]).is_err() {
            eprintln!("WARNING: Failed to set loc_gist_token secret");
        }
    }

    println!("\nRepository {repo_name} created successfully!");
}

fn main() {
    let args = Args::parse();

    match args.command {
        Commands::Fork { message } => fork(message),
        Commands::Pr {
            target_branch,
            draft,
        } => pr(target_branch, draft),
        Commands::Push { force_with_lease, force, args } => push(force_with_lease, force, args),
        Commands::Delete { branch } => delete(branch),
        Commands::Publish { repo_name, private, public, commit } => publish(repo_name, private, public, commit),
    }
}
