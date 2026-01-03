#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::{Parser, ValueEnum};
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
            return Err(format!(
                "Invalid version format '{s}', expected 'v1.2.3' or '1.2.3'"
            ));
        }
        let p0 = parts[0];
        let major = p0.parse().map_err(|_| format!("Invalid major version: {p0}"))?;
        let p1 = parts[1];
        let minor = p1.parse().map_err(|_| format!("Invalid minor version: {p1}"))?;
        let p2 = parts[2];
        let patch = p2.parse().map_err(|_| format!("Invalid patch version: {p2}"))?;
        Ok(Version {
            major,
            minor,
            patch,
        })
    }
}

impl std::fmt::Display for Version {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

impl PartialEq for Version {
    fn eq(&self, other: &Self) -> bool {
        self.major == other.major && self.minor == other.minor && self.patch == other.patch
    }
}

impl Eq for Version {}

impl PartialOrd for Version {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Version {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        match self.major.cmp(&other.major) {
            std::cmp::Ordering::Equal => match self.minor.cmp(&other.minor) {
                std::cmp::Ordering::Equal => self.patch.cmp(&other.patch),
                other => other,
            },
            other => other,
        }
    }
}

impl Version {
    fn bump_patch(self) -> Self {
        Version {
            major: self.major,
            minor: self.minor,
            patch: self.patch + 1,
        }
    }

    fn bump_minor(self) -> Self {
        Version {
            major: self.major,
            minor: self.minor + 1,
            patch: 0,
        }
    }

    fn bump_major(self) -> Self {
        Version {
            major: self.major + 1,
            minor: 0,
            patch: 0,
        }
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
    #[arg(short = 'v', long = "version", conflicts_with_all = ["patch", "minor", "major"])]
    version: Option<Version>,

    /// Bump patch version from latest tag (e.g., v1.2.3 -> v1.2.4)
    #[arg(long, conflicts_with_all = ["version", "minor", "major"])]
    patch: bool,

    /// Bump minor version from latest tag (e.g., v1.2.3 -> v1.3.0)
    #[arg(long, conflicts_with_all = ["version", "patch", "major"])]
    minor: bool,

    /// Bump major version from latest tag (e.g., v1.2.3 -> v2.0.0)
    #[arg(long, conflicts_with_all = ["version", "patch", "minor"])]
    major: bool,
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

fn get_latest_tag() -> Option<Version> {
    // Get all tags sorted by version (descending), filter for semver tags
    let output = run_output("git", &["tag", "--list", "v*"])?;
    output
        .lines()
        .filter_map(|tag| tag.parse::<Version>().ok())
        .max()
}

mod rust {
    use super::{SemverBump, run};
    use std::fs;
    use std::path::Path;

    pub fn has_cargo_toml() -> bool {
        Path::new("Cargo.toml").exists()
    }

    pub fn bump_version(bump: SemverBump) -> Result<(), String> {
        let cargo_toml_path = "Cargo.toml";
        let content = fs::read_to_string(cargo_toml_path)
            .map_err(|e| format!("Failed to read {cargo_toml_path}: {e}"))?;

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
                if let Some(start) = line.find('"')
                    && let Some(end) = line.rfind('"')
                {
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

                        let new_version = format!("{new_major}.{new_minor}.{new_patch}");
                        let prefix = &line[..start + 1];
                        let suffix = &line[end..];
                        new_lines.push(format!("{prefix}{new_version}{suffix}"));
                        version_bumped = true;
                        println!("Bumped version: {version_str} -> {new_version}");
                        continue;
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
            .map_err(|e| format!("Failed to write {cargo_toml_path}: {e}"))?;

        Ok(())
    }

    pub fn run_sed_deps() -> bool {
        let home = std::env::var("HOME").unwrap_or_default();
        let sed_deps = format!("{home}/s/g/github/github/workflows/pre_ci_sed_deps.rs");
        if !run(&sed_deps, &["."]) {
            eprintln!("error: sed-deps failed");
            return false;
        }
        true
    }

    pub fn test_and_build() -> bool {
        if !run("cargo", &["t"]) {
            eprintln!("error: cargo test failed");
            return false;
        }

        if !run("nix", &["build"]) {
            eprintln!("error: nix build failed");
            return false;
        }
        true
    }
}

fn has_uncommitted_changes() -> bool {
    // Check for staged, unstaged, or untracked files
    let status = run_output("git", &["status", "--porcelain"]);
    match status {
        Some(output) => !output.is_empty(),
        None => false,
    }
}

fn get_default_branch() -> Option<String> {
    // Check if master exists, otherwise check for main
    if run("git", &["show-ref", "--verify", "--quiet", "refs/heads/master"]) {
        Some("master".to_string())
    } else if run("git", &["show-ref", "--verify", "--quiet", "refs/heads/main"]) {
        Some("main".to_string())
    } else {
        None
    }
}

fn main() {
    let args = Args::parse();
    let is_rust = rust::has_cargo_toml();

    // Determine default branch (master or main)
    let default_branch = match get_default_branch() {
        Some(b) => b,
        None => {
            eprintln!("error: no master or main branch found");
            exit(1);
        }
    };

    // Must be on default branch to release
    let cur_branch = run_output("git", &["symbolic-ref", "--short", "HEAD"]);
    if cur_branch.as_deref() != Some(default_branch.as_str()) {
        let cur = cur_branch.as_deref().unwrap_or("unknown");
        eprintln!("error: must be on {default_branch} branch to release (currently on {cur})");
        eprintln!("hint: it doesn't make sense to release changes that haven't been merged into {default_branch} yet");
        exit(1);
    }

    // Check for uncommitted changes
    if has_uncommitted_changes() && args.commit_message.is_none() {
        eprintln!(
            "error: uncommitted changes detected. Provide a commit message to commit them first, or manually commit/stash them."
        );
        exit(1);
    }

    // If commit message provided, bump version (if rust) and commit on default branch first
    if let Some(ref msg) = args.commit_message {
        if is_rust {
            if let Err(e) = rust::bump_version(args.semver) {
                eprintln!("error bumping version: {e}");
                exit(1);
            }
        }

        // Stage all files (including untracked) and commit
        if !run("git", &["add", "-A"]) {
            eprintln!("error: git add failed");
            exit(1);
        }
        let _ = run("git", &["commit", "-m", msg]);

        // Push commit to default branch
        if !run("git", &["push", "origin", &default_branch]) {
            eprintln!("error: failed to push to {default_branch}");
            exit(1);
        }
    }

    // Create/update release branch from default branch
    if !run("git", &["branch", "-f", "release", &default_branch]) {
        eprintln!("error: failed to create release branch");
        exit(1);
    }

    // Checkout release
    if !run("git", &["checkout", "release"]) {
        eprintln!("error: failed to checkout release");
        exit(1);
    }

    // Track whether rust validation passed (for deciding whether to abort release push)
    let mut rust_validation_failed = false;

    if is_rust {
        // Run sed-deps to rewrite Cargo.toml
        if !rust::run_sed_deps() {
            if !args.fast {
                rust_validation_failed = true;
            }
        }

        // Test and build unless fast mode
        if !args.fast && !rust_validation_failed {
            if !rust::test_and_build() {
                rust_validation_failed = true;
            }
        } else if args.fast {
            println!("Fast mode: skipping tests and build");
        }
    }

    // If rust validation failed (and not fast mode), abort release branch push but exit with error
    if rust_validation_failed {
        eprintln!("error: aborting release due to validation failures");
        let _ = run("git", &["checkout", &default_branch]);
        exit(1);
    }

    // Stage all changes
    if !run("git", &["add", "-A"]) {
        eprintln!("error: git add failed");
        let _ = run("git", &["checkout", &default_branch]);
        exit(1);
    }

    // Commit (ignore error if nothing to commit)
    let _ = run("git", &["commit", "-m", "upload"]);

    // Force push to origin release
    if !run("git", &["push", "--force", "origin", "release"]) {
        eprintln!("error: git push failed");
        let _ = run("git", &["checkout", &default_branch]);
        exit(1);
    }

    // Return to default branch
    if !run("git", &["checkout", &default_branch]) {
        exit(1);
    }

    // Determine version: either explicit, or computed from bump flags
    let version = if let Some(v) = args.version {
        // Check against latest existing tag
        if let Some(latest) = get_latest_tag() {
            if v < latest {
                eprintln!("error: version v{v} is smaller than the latest tag v{latest}");
                exit(1);
            } else if v == latest {
                eprintln!("warning: version v{v} is the same as the latest tag");
            }
        }
        Some(v)
    } else if args.patch || args.minor || args.major {
        let latest = match get_latest_tag() {
            Some(v) => v,
            None => {
                eprintln!("error: no existing version tags found, cannot bump. Use -v to set an initial version.");
                exit(1);
            }
        };
        let new_version = if args.patch {
            latest.bump_patch()
        } else if args.minor {
            latest.bump_minor()
        } else {
            latest.bump_major()
        };
        println!("Bumping version: v{latest} -> v{new_version}");
        Some(new_version)
    } else {
        None
    };

    // If version determined, tag and push to version branches
    if let Some(version) = version {
        let tag = format!("v{version}");
        let major_branch = format!("v{}", version.major);
        let minor_branch = format!("v{}.{}", version.major, version.minor);

        // Create and push tag on default branch (don't fail if already exists)
        let _ = run("git", &["tag", "-f", &tag]);
        if run("git", &["push", "--force", "origin", &tag]) {
            println!("Tagged and pushed {tag}");
        } else {
            println!("Tag {tag} already exists on remote, continuing");
        }

        // Push to version branches (create if they don't exist)
        for branch in [&major_branch, &minor_branch] {
            // Create/update branch pointing to default branch
            if !run("git", &["branch", "-f", branch, &default_branch]) {
                eprintln!("error: failed to create branch {branch}");
                exit(1);
            }
            if !run("git", &["push", "--force", "origin", branch]) {
                eprintln!("error: failed to push branch {branch}");
                exit(1);
            }
            println!("Pushed to branch {branch}");
        }
    }

    println!("Release pushed successfully!");
}
