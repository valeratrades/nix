#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde_json = "1"
---

use clap::Parser;
use std::env;
use std::process::{Command, Stdio};

/// Create a new GitHub repository with standard labels and milestones
#[derive(Parser, Debug)]
#[command(name = "gn")]
#[command(about = "Create a new GitHub repository with standard labels and milestones")]
struct Args {
    /// Repository name (defaults to current directory name)
    #[arg()]
    repo_name: Option<String>,

    /// Create a private repository
    #[arg(long, conflicts_with = "public")]
    private: bool,

    /// Create a public repository
    #[arg(long, conflicts_with = "private")]
    public: bool,
}

struct Label {
    name: &'static str,
    color: &'static str,
    description: &'static str,
}

const LABELS: &[Label] = &[
    // Custom labels
    Label { name: "ci", color: "808080", description: "New test or benchmark" },
    Label { name: "chore", color: "0052CC", description: "Small non-imaginative task" },
    Label { name: "breaking", color: "000000", description: "Implementing should be postponed until next major version" },
    Label { name: "hack", color: "FF8C00", description: "Hacky feature" },
    Label { name: "rewrite", color: "008672", description: "Code quality" },
    // Default GitHub labels
    Label { name: "enhancement", color: "a2eeef", description: "New feature or request" },
    Label { name: "bug", color: "d73a4a", description: "Something isn't working" },
    Label { name: "documentation", color: "0075ca", description: "Improvements or additions to documentation" },
    Label { name: "duplicate", color: "cfd3d7", description: "This issue or pull request already exists" },
    Label { name: "good first issue", color: "7057ff", description: "Good for newcomers" },
    Label { name: "help wanted", color: "008672", description: "Extra attention is needed" },
    Label { name: "invalid", color: "e4e669", description: "This doesn't seem right" },
    Label { name: "question", color: "d876e3", description: "Further information is requested" },
    Label { name: "wontfix", color: "ffffff", description: "This will not be worked on" },
];

struct Milestone {
    title: &'static str,
    description: &'static str,
}

const MILESTONES: &[Milestone] = &[
    Milestone { title: "1.0", description: "Minimum viable product" },
    Milestone { title: "2.0", description: "Fix bugs, rewrite hacks" },
    Milestone { title: "3.0", description: "More and better" },
];

fn run_cmd(cmd: &str, args: &[&str]) -> bool {
    Command::new(cmd)
        .args(args)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
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

fn create_label(github_name: &str, repo_name: &str, label: &Label) {
    let name = label.name;
    let color = label.color;
    let description = label.description;
    let output = Command::new("gh")
        .args([
            "api",
            &format!("repos/{github_name}/{repo_name}/labels"),
            "-f", &format!("name={name}"),
            "-f", &format!("color={color}"),
            "-f", &format!("description={description}"),
        ])
        .output();

    match output {
        Ok(out) => {
            let stderr = String::from_utf8_lossy(&out.stderr);
            let stdout = String::from_utf8_lossy(&out.stdout);
            if stderr.contains("already_exists") || stdout.contains("already_exists") {
                println!("Label '{name}' already exists, skipping...");
            } else if out.status.success() {
                println!("Successfully created: '{name}'");
            } else {
                eprintln!("ERROR creating '{name}': {stderr}");
            }
        }
        Err(e) => eprintln!("Failed to create label '{name}': {e}"),
    }
}

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

fn main() {
    let args = Args::parse();

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
    let repo_name = args.repo_name.unwrap_or_else(|| {
        env::current_dir()
            .ok()
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
            .unwrap_or_else(|| {
                eprintln!("ERROR: Could not determine repository name");
                std::process::exit(1);
            })
    });

    // Determine visibility flag
    let visibility = if args.private {
        "--private"
    } else if args.public {
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

    // git add .
    if !run_cmd("git", &["add", "."]) {
        eprintln!("ERROR: git add failed");
        std::process::exit(1);
    }

    // git commit
    if !run_cmd("git", &["commit", "-m", "Initial Commit"]) {
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

    // Create labels
    println!("\nCreating labels...");
    for label in LABELS {
        create_label(&github_name, &repo_name, label);
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
