#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde_json = "1"
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
    if origin_url.contains(&format!("github.com/{github_name}/"))
        || origin_url.contains(&format!("github.com:{github_name}/"))
    {
        println!("Origin already points to your repo, running gg...");
        // Ensure branch tracks origin (might still track upstream from previous fork setup)
        if let Some(branch) = run_cmd_output("git", &["rev-parse", "--abbrev-ref", "HEAD"]) {
            let tracking = run_cmd_output("git", &["config", &format!("branch.{branch}.remote")]);
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

    println!("Pushing to {fork_url} ...");

    // Initial push to fork with -u to set up tracking (branch now tracks origin instead of upstream)
    if let Some(branch) = run_cmd_output("git", &["rev-parse", "--abbrev-ref", "HEAD"])
        && !run_cmd("git", &["push", "-u", "origin", &branch])
    {
        eprintln!("ERROR: Failed to push to fork");
        std::process::exit(1);
    }

    run_gg(&message);
}

fn get_default_branch() -> Option<String> {
    // Try to get the default branch from GitHub via gh CLI
    run_cmd_output("gh", &["repo", "view", "--json", "defaultBranchRef", "-q", ".defaultBranchRef.name"])
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

    let pr_already_exists = match &pr_create_output {
        Ok(o) => String::from_utf8_lossy(&o.stderr).contains("already exists"),
        Err(_) => false,
    };

    if !pr_already_exists
        && !pr_create_output
            .map(|o| o.status.success())
            .unwrap_or(false)
    {
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
            eprintln!("ERROR: Could not find PR number for '{current_branch}'");
            std::process::exit(1);
        }
    };

    println!("Merging PR #{pr_number}");

    // Checkout target branch
    if !run_cmd("git", &["checkout", &target_branch]) {
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
    run_cmd("git", &["pull"]);

    println!("Successfully merged '{current_branch}' into '{target_branch}'");
}

const GIT_SHARED_MAIN_BRANCHES: &[&str] = &["master", "main", "release", "stg", "prod"];

fn is_main_branch(branch: &str) -> bool {
    GIT_SHARED_MAIN_BRANCHES.contains(&branch)
}

fn push(force_with_lease: bool, force: bool, extra_args: Vec<String>) {
    if !run_cmd_quiet("git", &["rev-parse", "--is-inside-work-tree"]) {
        eprintln!("ERROR: Not in a git repository");
        std::process::exit(1);
    }

    let branch = match run_cmd_output("git", &["rev-parse", "--abbrev-ref", "HEAD"]) {
        Some(b) if !b.is_empty() => b,
        _ => {
            eprintln!("ERROR: Could not get current branch");
            std::process::exit(1);
        }
    };

    let use_force = force;
    let mut use_force_with_lease = force_with_lease;
    let explicit_force = force_with_lease || force;

    // Check if we need a force push and whether it's safe
    let local_tree = run_cmd_output("git", &["rev-parse", "HEAD^{tree}"]);
    let remote_tree = run_cmd_output("git", &["rev-parse", &format!("origin/{branch}^{{tree}}")]);
    let remote_is_ancestor = run_cmd_quiet("git", &["merge-base", "--is-ancestor", &format!("origin/{branch}"), "HEAD"]);
    let local_is_ancestor = run_cmd_quiet("git", &["merge-base", "--is-ancestor", "HEAD", &format!("origin/{branch}")]);

    // Determine if force push would be safe
    let trees_match = matches!((&local_tree, &remote_tree), (Some(local), Some(remote)) if local == remote);

    // Check if we actually need a force push (histories diverged)
    let needs_force = !local_is_ancestor && !remote_is_ancestor;

    // Check if divergence is due to commit renames only (even with new commits on top)
    // This handles: local has A'-B-C, remote has A, where A' is A with different message
    let divergence_is_rename_only = needs_force && {
        // Find the merge-base (common ancestor)
        let merge_base = run_cmd_output("git", &["merge-base", "HEAD", &format!("origin/{branch}")]);
        if let Some(base) = merge_base {
            // Get commits on remote since merge-base
            let remote_commits = run_cmd_output(
                "git",
                &["rev-list", "--reverse", &format!("{base}..origin/{branch}")],
            );
            // Get commits on local since merge-base
            let local_commits = run_cmd_output(
                "git",
                &["rev-list", "--reverse", &format!("{base}..HEAD")],
            );

            match (remote_commits, local_commits) {
                (Some(remote), Some(local)) => {
                    let remote_list: Vec<&str> = remote.lines().collect();
                    let local_list: Vec<&str> = local.lines().collect();

                    // Remote commits must be a prefix (in terms of trees) of local commits
                    // i.e., for each remote commit, there's a corresponding local commit with same tree
                    if !remote_list.is_empty() && local_list.len() >= remote_list.len() {
                        remote_list.iter().zip(local_list.iter()).all(|(r, l)| {
                            let r_tree = run_cmd_output("git", &["rev-parse", &format!("{r}^{{tree}}")]);
                            let l_tree = run_cmd_output("git", &["rev-parse", &format!("{l}^{{tree}}")]);
                            matches!((r_tree, l_tree), (Some(rt), Some(lt)) if rt == lt)
                        })
                    } else {
                        false
                    }
                }
                _ => false,
            }
        } else {
            false
        }
    };

    if explicit_force && is_main_branch(&branch) {
        // User explicitly requested force - check if it's safe on main branches
        if trees_match {
            println!("Trees match - only commit structure changed. Allowing force push on {branch}.");
        } else if remote_is_ancestor {
            println!("Remote is ancestor of local - squashed commits. Allowing force push on {branch}.");
        } else if divergence_is_rename_only {
            println!("Divergence is commit renames only (with new commits on top). Allowing force push on {branch}.");
        } else {
            eprintln!("Refusing to force push {branch} (tree content differs and remote is not ancestor)");
            std::process::exit(1);
        }
    } else if !explicit_force && needs_force {
        // No explicit force flag, but histories diverged - auto-force if safe
        if trees_match {
            println!("Trees match (only commit messages/structure changed) - auto-enabling force-with-lease.");
            use_force_with_lease = true;
        } else if remote_is_ancestor {
            println!("Remote is ancestor of local (squashed commits) - auto-enabling force-with-lease.");
            use_force_with_lease = true;
        } else if divergence_is_rename_only {
            println!("Divergence is commit renames only (with new commits on top) - auto-enabling force-with-lease.");
            use_force_with_lease = true;
        }
        // If not safe, let git push fail naturally with its error message
    }

    let extra_refs: Vec<&str> = extra_args.iter().map(|s| s.as_str()).collect();

    let mut args = vec!["push"];
    if use_force {
        args.push("--force");
    } else if use_force_with_lease {
        args.push("--force-with-lease");
    }
    args.push("--follow-tags");
    args.extend(extra_refs);

    if !run_cmd("git", &args) {
        std::process::exit(1);
    }
}

fn delete(branch: String) {
    if !run_cmd_quiet("git", &["rev-parse", "--is-inside-work-tree"]) {
        eprintln!("ERROR: Not in a git repository");
        std::process::exit(1);
    }

    if is_main_branch(&branch) {
        eprintln!("Refusing to delete {branch}");
        std::process::exit(1);
    }

    // Delete local branch
    if !run_cmd("git", &["branch", "-D", &branch]) {
        eprintln!("ERROR: Failed to delete local branch {branch}");
        std::process::exit(1);
    }

    // Delete remote branch
    if !run_cmd("git", &["push", "origin", "--delete", &branch]) {
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
    if !run_cmd("git", &["init"]) {
        eprintln!("ERROR: git init failed");
        std::process::exit(1);
    }

    // git add . and commit
    if !run_cmd("git", &["add", "."]) {
        eprintln!("ERROR: git add failed");
        std::process::exit(1);
    }

    let commit_msg = commit.as_deref().unwrap_or("Initial Commit");
    if !run_cmd("git", &["commit", "-m", commit_msg]) {
        eprintln!("ERROR: git commit failed");
        std::process::exit(1);
    }

    // gh repo create
    if !run_cmd("gh", &["repo", "create", &repo_name, visibility, "--source=."]) {
        eprintln!("ERROR: gh repo create failed");
        std::process::exit(1);
    }

    // git remote add origin
    let remote_url = format!("https://github.com/{github_name}/{repo_name}.git");
    // Remove existing origin if any, then add
    run_cmd_quiet("git", &["remote", "remove", "origin"]);
    if !run_cmd("git", &["remote", "add", "origin", &remote_url]) {
        eprintln!("ERROR: git remote add failed");
        std::process::exit(1);
    }

    // git push
    if !run_cmd("git", &["push", "-u", "origin", "master"]) {
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
        if !run_cmd("gh", &["secret", "set", "loc_gist_token", "--repo", &full_repo, "--body", &loc_gist]) {
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
