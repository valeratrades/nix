#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
gix = { version = "0.78", features = ["merge"] }
serde_json = "1"
---

use clap::{Parser, Subcommand};
use gix::merge::tree::TreatAsUnresolved;
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

/// Run command with inherited stdio (user sees output)
fn run_cmd(cmd: &str, args: &[&str]) -> bool {
    Command::new(cmd)
        .args(args)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Run command and capture stdout
fn run_cmd_output(cmd: &str, args: &[&str]) -> Option<String> {
    Command::new(cmd)
        .args(args)
        .stderr(Stdio::null())
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
}

/// Run command silently, returns true if success
fn run_cmd_status(cmd: &str, args: &[&str]) -> bool {
    Command::new(cmd)
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Equivalent to `gg` fish function: git add -A && git commit -am "msg" && git push
fn run_gg(message: &[String]) {
    let msg = if message.is_empty() {
        "_".to_string()
    } else {
        message.join(" ")
    };

    if !run_cmd("git", &["add", "-A"]) {
        eprintln!("ERROR: git add failed");
        std::process::exit(1);
    }

    // Commit - may fail if nothing to commit, that's ok
    let commit_status = Command::new("git")
        .args(["commit", "-am", &msg])
        .status();

    if let Ok(status) = commit_status {
        if !status.success() {
            // Check if it's just "nothing to commit"
            let check = Command::new("git")
                .args(["status", "--porcelain"])
                .output();
            if check.map(|o| o.stdout.is_empty()).unwrap_or(false) {
                // Nothing to commit, but we should still push
            } else {
                eprintln!("ERROR: git commit failed");
                std::process::exit(1);
            }
        }
    }

    if !run_cmd("git", &["push"]) {
        std::process::exit(1);
    }
}

fn open_repo() -> gix::Repository {
    gix::discover(".").unwrap_or_else(|e| {
        eprintln!("ERROR: Not in a git repository: {e}");
        std::process::exit(1);
    })
}

fn current_branch(repo: &gix::Repository) -> Option<String> {
    repo.head_name()
        .ok()
        .flatten()
        .map(|n| n.shorten().to_string())
}

fn branch_tracking_remote(repo: &gix::Repository, branch: &str) -> Option<String> {
    let config = repo.config_snapshot();
    let key = format!("branch.{branch}.remote");
    config.string(&key).map(|s| s.to_string())
}

fn remote_exists(repo: &gix::Repository, name: &str) -> bool {
    repo.find_remote(name).is_ok()
}

fn fork(message: Vec<String>) {
    let repo = open_repo();

    let github_name = match env::var("GITHUB_NAME") {
        Ok(v) => v,
        Err(_) => {
            eprintln!("ERROR: GITHUB_NAME is not set");
            std::process::exit(1);
        }
    };

    let origin_url = match repo.find_remote("origin") {
        Ok(remote) => remote.url(gix::remote::Direction::Push).map(|u| u.to_bstring().to_string()),
        Err(_) => None,
    };

    let origin_url = match origin_url {
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
        if let Some(branch) = current_branch(&repo) {
            let tracking = branch_tracking_remote(&repo, &branch);
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
    let has_upstream = remote_exists(&repo, "upstream");

    if has_upstream {
        // upstream exists, just update origin
        run_cmd("git", &["remote", "set-url", "origin", &fork_url]);
    } else {
        // Rename origin to upstream, add fork as origin
        run_cmd_status("git", &["remote", "rename", "origin", "upstream"]);
        if !run_cmd_status("git", &["remote", "add", "origin", &fork_url]) {
            run_cmd("git", &["remote", "set-url", "origin", &fork_url]);
        }
    }

    println!("Pushing to {fork_url} ...");

    // Initial push to fork with -u to set up tracking (branch now tracks origin instead of upstream)
    if let Some(branch) = current_branch(&repo) {
        if !run_cmd("git", &["push", "-u", "origin", &branch]) {
            eprintln!("ERROR: Failed to push to fork");
            std::process::exit(1);
        }
    }

    run_gg(&message);
}

fn get_default_branch() -> Option<String> {
    // Try to get the default branch from GitHub via gh CLI
    run_cmd_output(
        "gh",
        &[
            "repo",
            "view",
            "--json",
            "defaultBranchRef",
            "-q",
            ".defaultBranchRef.name",
        ],
    )
}

fn pr(target_branch: Option<String>, draft: bool) {
    let repo = open_repo();

    let current_branch = match current_branch(&repo) {
        Some(b) => b,
        None => {
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
            if !run_cmd("gh", &["pr", "ready"]) {
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

/// Check if one commit is an ancestor of another using gix
fn is_ancestor(repo: &gix::Repository, ancestor: gix::ObjectId, descendant: gix::ObjectId) -> bool {
    if ancestor == descendant {
        return true;
    }
    repo.merge_base(ancestor, descendant)
        .map(|mb| mb == ancestor)
        .unwrap_or(false)
}

/// Check if merging their_tree into our_tree would have conflicts
fn merge_would_conflict(
    repo: &gix::Repository,
    base_tree: gix::ObjectId,
    our_tree: gix::ObjectId,
    their_tree: gix::ObjectId,
) -> bool {
    let outcome = repo.merge_trees(
        base_tree,
        our_tree,
        their_tree,
        Default::default(),
        Default::default(),
    );

    match outcome {
        Ok(result) => result.has_unresolved_conflicts(TreatAsUnresolved::default()),
        Err(_) => true, // assume conflict on error
    }
}

/// Check if two trees have the same content (ignoring history)
fn trees_have_same_content(
    _repo: &gix::Repository,
    tree1: gix::ObjectId,
    tree2: gix::ObjectId,
) -> bool {
    // Trees with same OID have identical content
    tree1 == tree2
}

/// Check if remote's tree appears in local's commit history
fn remote_tree_in_local_history(
    repo: &gix::Repository,
    local_commit: gix::ObjectId,
    remote_tree: gix::ObjectId,
) -> bool {
    let Ok(walk) = repo.rev_walk([local_commit]).all() else {
        return false;
    };

    for info in walk {
        let Ok(info) = info else { continue };
        let Ok(obj) = info.id().object() else { continue };
        let Ok(commit) = obj.try_into_commit() else { continue };
        let Ok(tree_id) = commit.tree_id() else { continue };
        if tree_id.detach() == remote_tree {
            return true;
        }
    }
    false
}

fn push(force_with_lease: bool, force: bool, extra_args: Vec<String>) {
    let repo = open_repo();

    let branch = match repo.head_name() {
        Ok(Some(name)) => name.shorten().to_string(),
        _ => {
            eprintln!("ERROR: Could not get current branch (detached HEAD?)");
            std::process::exit(1);
        }
    };

    // Fetch the remote branch to ensure we have up-to-date refs for comparison
    let fetch_refspec = format!("{branch}:refs/remotes/origin/{branch}");
    if !run_cmd("git", &["fetch", "origin", &fetch_refspec]) {
        eprintln!("ERROR: Failed to fetch origin/{branch}");
        std::process::exit(1);
    }

    // Re-open repo to get fresh refs after fetch
    let repo = open_repo();

    // Get local HEAD commit
    let local_commit = match repo.head_commit() {
        Ok(c) => c.id,
        Err(e) => {
            eprintln!("ERROR: Could not get HEAD commit: {e}");
            std::process::exit(1);
        }
    };

    // Get remote commit
    let remote_ref_name = format!("refs/remotes/origin/{branch}");
    let remote_commit = repo
        .find_reference(&remote_ref_name)
        .ok()
        .and_then(|mut r| r.peel_to_id().ok())
        .map(|id| id.detach());

    let remote_commit = match remote_commit {
        Some(c) => c,
        None => {
            // No remote branch yet, just push normally
            let extra_refs: Vec<&str> = extra_args.iter().map(|s| s.as_str()).collect();
            let mut args = vec!["push", "--follow-tags"];
            args.extend(extra_refs);
            if !run_cmd("git", &args) {
                std::process::exit(1);
            }
            return;
        }
    };

    let use_force = force;
    let mut use_force_with_lease = force_with_lease;
    let explicit_force = force_with_lease || force;

    // Get tree IDs
    let local_tree = repo
        .head_commit()
        .ok()
        .and_then(|c| c.tree_id().ok())
        .map(|id| id.detach());
    let remote_tree = repo
        .find_object(remote_commit)
        .ok()
        .and_then(|o| o.peel_to_commit().ok())
        .and_then(|c| c.tree_id().ok())
        .map(|id| id.detach());

    // Check ancestor relationships
    let remote_is_ancestor = is_ancestor(&repo, remote_commit, local_commit);
    let local_is_ancestor = is_ancestor(&repo, local_commit, remote_commit);

    // Determine if force push would be safe
    let trees_match = matches!((&local_tree, &remote_tree), (Some(l), Some(r)) if l == r);

    // Check if we actually need a force push (histories diverged)
    let needs_force = !local_is_ancestor && !remote_is_ancestor;

    // Check if local contains remote's content
    let local_contains_remote_content = needs_force && {
        let (local_tree, remote_tree) = match (&local_tree, &remote_tree) {
            (Some(l), Some(r)) => (*l, *r),
            _ => {
                // Can't check, assume unsafe
                (gix::ObjectId::null(gix::hash::Kind::Sha1), gix::ObjectId::null(gix::hash::Kind::Sha1))
            }
        };

        // Check 1: exact tree match in history
        let tree_in_history = remote_tree_in_local_history(&repo, local_commit, remote_tree);

        // Check 2: merging remote into local would be conflict-free
        // Find merge-base to use as ancestor for three-way merge simulation
        let merge_would_be_clean = repo
            .merge_base(local_commit, remote_commit)
            .ok()
            .map(|base| {
                let base_tree = repo
                    .find_object(base)
                    .ok()
                    .and_then(|o| o.peel_to_commit().ok())
                    .and_then(|c| c.tree_id().ok())
                    .map(|id| id.detach());

                match base_tree {
                    Some(base_tree) => !merge_would_conflict(&repo, base_tree, local_tree, remote_tree),
                    None => false,
                }
            })
            .unwrap_or(false);

        // Check 3: no actual content difference (just history rewrite)
        let no_content_diff = trees_have_same_content(&repo, local_tree, remote_tree);

        tree_in_history || merge_would_be_clean || no_content_diff
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
        force_with_lease_arg = format!("--force-with-lease=refs/heads/{branch}:{remote_commit}");
        args.push(&force_with_lease_arg);
    }
    args.push("--follow-tags");
    args.extend(extra_refs);

    if !run_cmd("git", &args) {
        std::process::exit(1);
    }
}

fn delete(branch: String) {
    let _ = open_repo(); // verify we're in a repo

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
    Milestone {
        title: "1.0",
        description: "Minimum viable product",
    },
    Milestone {
        title: "2.0",
        description: "Fix bugs, rewrite hacks",
    },
    Milestone {
        title: "3.0",
        description: "More and better",
    },
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
            "-L",
            "-X",
            "POST",
            "-H",
            "Accept: application/vnd.github+json",
            "-H",
            &format!("Authorization: token {github_key}"),
            "-H",
            "X-GitHub-Api-Version: 2022-11-28",
            &format!("https://api.github.com/repos/{github_name}/{repo_name}/milestones"),
            "-d",
            &body.to_string(),
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
    if !run_cmd("gh", &["repo", "create", &repo_name, visibility, "--source=."]) {
        eprintln!("ERROR: gh repo create failed");
        std::process::exit(1);
    }

    // git remote add origin
    let remote_url = format!("https://github.com/{github_name}/{repo_name}.git");
    // Remove existing origin if any, then add
    run_cmd_status("git", &["remote", "remove", "origin"]);
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
        if !run_cmd(
            "gh",
            &[
                "secret",
                "set",
                "loc_gist_token",
                "--repo",
                &full_repo,
                "--body",
                &loc_gist,
            ],
        ) {
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
        Commands::Push {
            force_with_lease,
            force,
            args,
        } => push(force_with_lease, force, args),
        Commands::Delete { branch } => delete(branch),
        Commands::Publish {
            repo_name,
            private,
            public,
            commit,
        } => publish(repo_name, private, public, commit),
    }
}
