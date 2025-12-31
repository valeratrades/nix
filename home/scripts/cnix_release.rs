#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::{Parser, ValueEnum};
use std::fs;
use std::process::{Command, exit};
use std::str::FromStr;

#[derive(Debug, Clone, Copy)]
struct Version {
    major: u32,
    minor: u32,
    patch: u32,
}

impl FromStr for Version {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let s = s.strip_prefix('v').unwrap_or(s);
        let parts: Vec<&str> = s.split('.').collect();
        if parts.len() != 3 {
            return Err(format!("Invalid version format '{}', expected 'v1.2.3' or '1.2.3'", s));
        }
        let major = parts[0].parse().map_err(|_| format!("Invalid major version: {}", parts[0]))?;
        let minor = parts[1].parse().map_err(|_| format!("Invalid minor version: {}", parts[1]))?;
        let patch = parts[2].parse().map_err(|_| format!("Invalid patch version: {}", parts[2]))?;
        Ok(Version { major, minor, patch })
    }
}

impl std::fmt::Display for Version {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

#[derive(Debug, Clone, Copy, ValueEnum, Default)]
enum SemverBump {
    Patch,
    #[default]
    Minor,
    Major,
}

/// Release for nix-consumed crates (rewrites path deps to git deps on release branch)
#[derive(Parser, Debug)]
#[command(name = "cnix_release")]
#[command(about = "Release for nix-consumed crates")]
struct Args {
    /// Git commit message - if provided, commits on master before switching to release
    commit_message: Option<String>,

    /// Semver bump type (defaults to minor)
    #[arg(short, long, value_enum, default_value = "minor")]
    semver: SemverBump,

    /// Fast mode: skip tests and nix build
    #[arg(short, long)]
    fast: bool,

    /// Version to tag (e.g., v1.2.3 or 1.2.3)
    #[arg(short = 'v', long = "version")]
    version: Option<Version>,
}

fn run(cmd: &str, args: &[&str]) -> bool {
    Command::new(cmd)
        .args(args)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn run_output(cmd: &str, args: &[&str]) -> Option<String> {
    Command::new(cmd).args(args).output().ok().and_then(|o| {
        if o.status.success() {
            Some(String::from_utf8_lossy(&o.stdout).trim().to_string())
        } else {
            None
        }
    })
}

fn bump_version(cargo_toml_path: &str, bump: SemverBump) -> Result<(), String> {
    let content = fs::read_to_string(cargo_toml_path)
        .map_err(|e| format!("Failed to read {}: {}", cargo_toml_path, e))?;

    let mut in_package = false;
    let mut new_lines = Vec::new();
    let mut version_bumped = false;

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed == "[package]" {
            in_package = true;
            new_lines.push(line.to_string());
        } else if trimmed.starts_with('[') {
            in_package = false;
            new_lines.push(line.to_string());
        } else if in_package && trimmed.starts_with("version") {
            // Parse version line like: version = "1.2.3"
            if let Some(start) = line.find('"') {
                if let Some(end) = line.rfind('"') {
                    let version_str = &line[start + 1..end];
                    let parts: Vec<&str> = version_str.split('.').collect();
                    if parts.len() == 3 {
                        let major: u32 = parts[0].parse().map_err(|_| "Invalid major version")?;
                        let minor: u32 = parts[1].parse().map_err(|_| "Invalid minor version")?;
                        let patch: u32 = parts[2].parse().map_err(|_| "Invalid patch version")?;

                        let (new_major, new_minor, new_patch) = match bump {
                            SemverBump::Major => (major + 1, 0, 0),
                            SemverBump::Minor => (major, minor + 1, 0),
                            SemverBump::Patch => (major, minor, patch + 1),
                        };

                        let new_version = format!("{}.{}.{}", new_major, new_minor, new_patch);
                        let prefix = &line[..start + 1];
                        let suffix = &line[end..];
                        new_lines.push(format!("{}{}{}", prefix, new_version, suffix));
                        version_bumped = true;
                        println!("Bumped version: {} -> {}", version_str, new_version);
                        continue;
                    }
                }
            }
            new_lines.push(line.to_string());
        } else {
            new_lines.push(line.to_string());
        }
    }

    if !version_bumped {
        return Err("Could not find version in [package] section".to_string());
    }

    fs::write(cargo_toml_path, new_lines.join("\n") + "\n")
        .map_err(|e| format!("Failed to write {}: {}", cargo_toml_path, e))?;

    Ok(())
}

fn main() {
    let args = Args::parse();

    // Get current branch
    let cur_branch = run_output("git", &["symbolic-ref", "--short", "HEAD"])
        .unwrap_or_else(|| "master".to_string());

    // Check master branch exists
    if !run(
        "git",
        &["show-ref", "--verify", "--quiet", "refs/heads/master"],
    ) {
        eprintln!("error: no master branch");
        exit(1);
    }

    // If commit message provided, bump version and commit on master first
    if let Some(ref msg) = args.commit_message {
        // Bump version in Cargo.toml
        if let Err(e) = bump_version("Cargo.toml", args.semver) {
            eprintln!("error bumping version: {}", e);
            exit(1);
        }

        // Commit all changes
        if !run("git", &["commit", "-am", msg]) {
            eprintln!("error: git commit failed");
            exit(1);
        }
    }

    // Checkout master
    if !run("git", &["checkout", "master"]) {
        eprintln!("error: failed to checkout master");
        exit(1);
    }

    // Create/update release branch from master
    if !run("git", &["branch", "-f", "release", "master"]) {
        eprintln!("error: failed to create release branch");
        exit(1);
    }

    // Checkout release
    if !run("git", &["checkout", "release"]) {
        eprintln!("error: failed to checkout release");
        exit(1);
    }

    // Run sed-deps to rewrite Cargo.toml
    let home = std::env::var("HOME").unwrap_or_default();
    let sed_deps = format!("{home}/s/g/github/github/workflows/pre_ci_sed_deps.rs");
    if !run(&sed_deps, &["."]) {
        eprintln!("error: sed-deps failed");
        let _ = run("git", &["checkout", &cur_branch]);
        exit(1);
    }

    // Test and build unless fast mode
    if !args.fast {
        if !run("cargo", &["t"]) {
            eprintln!("error: cargo test failed");
            let _ = run("git", &["checkout", &cur_branch]);
            exit(1);
        }

        if !run("nix", &["build"]) {
            eprintln!("error: nix build failed");
            let _ = run("git", &["checkout", &cur_branch]);
            exit(1);
        }
    } else {
        println!("Fast mode enabled: Skipping tests and build steps");
    }

    // Stage all changes
    if !run("git", &["add", "-A"]) {
        eprintln!("error: git add failed");
        let _ = run("git", &["checkout", &cur_branch]);
        exit(1);
    }

    // Commit (ignore error if nothing to commit)
    let _ = run("git", &["commit", "-m", "upload"]);

    // Force push to origin release
    if !run("git", &["push", "--force", "origin", "release"]) {
        eprintln!("error: git push failed");
        let _ = run("git", &["checkout", &cur_branch]);
        exit(1);
    }

    // Return to master
    if !run("git", &["checkout", "master"]) {
        let _ = run("git", &["checkout", &cur_branch]);
        exit(1);
    }

    // If version provided, tag and push to version branches
    if let Some(version) = args.version {
        let tag = format!("v{}", version);
        let major_branch = format!("v{}", version.major);
        let minor_branch = format!("v{}.{}", version.major, version.minor);

        // Create and push tag on master
        if !run("git", &["tag", "-f", &tag]) {
            eprintln!("error: failed to create tag {}", tag);
            exit(1);
        }
        if !run("git", &["push", "--force", "origin", &tag]) {
            eprintln!("error: failed to push tag {}", tag);
            exit(1);
        }
        println!("Tagged and pushed {}", tag);

        // Push to version branches (create if they don't exist)
        for branch in [&major_branch, &minor_branch] {
            // Create/update branch pointing to master
            if !run("git", &["branch", "-f", branch, "master"]) {
                eprintln!("error: failed to create branch {}", branch);
                exit(1);
            }
            if !run("git", &["push", "--force", "origin", branch]) {
                eprintln!("error: failed to push branch {}", branch);
                exit(1);
            }
            println!("Pushed to branch {}", branch);
        }
    }

    println!("Release pushed successfully!");
}
