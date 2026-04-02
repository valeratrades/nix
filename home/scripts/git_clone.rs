#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4", features = ["derive"] }
---

use clap::Parser;
use std::{
    env,
    path::{Path, PathBuf},
    process::{Command, exit},
};

/// git clone on rails.
/// Give repo name, it clones into /tmp or provided directory.
///
/// ex 1: gc neovim/neovim .     # clone to current directory
/// ex 2: gc neovim/neovim       # clone to /tmp/neovim
/// ex 3: gc openai/gpt . -c     # clone to current directory and cd into it
#[derive(Parser)]
#[command(name = "gc")]
struct Args {
    /// Repository: "owner/repo", "repo" (uses $GITHUB_USERNAME), or full URL
    repo: String,

    /// Target directory (defaults to /tmp)
    target: Option<String>,

    /// Print the cloned path for shell cd integration
    #[arg(short)]
    c: bool,
}

fn clone_repo(args: &Args) -> Result<PathBuf, String> {
    let github_username = env::var("GITHUB_USERNAME").ok();

    let repo_payload = args.repo.trim_end_matches('/').to_string();
    let repo = if repo_payload.contains('/') {
        let (owner, repo) = repo_payload.split_once('/').unwrap();
        format!("{}/{}", owner, repo)
    } else if let Some(username) = github_username {
        format!("{}/{}", username, repo_payload)
    } else {
        return Err(
            "Owner is missing in the repository name, and $GITHUB_USERNAME is not set".to_string(),
        );
    };

    let url = if args.repo.contains("://") {
        repo_payload.clone()
    } else {
        format!("https://github.com/{}", repo)
    };

    let filename = Path::new(&url)
        .file_name()
        .map(|f| f.to_string_lossy().to_string())
        .unwrap_or_default()
        .trim_end_matches(".git")
        .to_string();

    let target = match &args.target {
        None => {
            let tmp_path = PathBuf::from(format!("/tmp/{}", filename));
            Command::new("rm")
                .arg("-rf")
                .arg(&tmp_path)
                .status()
                .map_err(|_| "Failed to remove existing directory".to_string())?;
            tmp_path
        }
        Some(t) => {
            if Path::new(t).is_dir() {
                PathBuf::from(t).join(&filename)
            } else {
                PathBuf::from(t)
            }
        }
    };

    let status = Command::new("git")
        .args(["clone", "--depth=1", &url, &target.display().to_string()])
        .status()
        .map_err(|_| "Failed to run git clone".to_string())?;

    if status.success() {
        Ok(target)
    } else {
        Err("Git clone failed".to_string())
    }
}

fn main() {
    let args = Args::parse();
    match clone_repo(&args) {
        Ok(path) => println!("{}", path.display()),
        Err(error) => {
            eprintln!("{}", error);
            exit(1);
        }
    }
}
