#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::Parser;
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

#[derive(Debug, Clone, Copy)]
enum SemverBump {
    Patch,
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
    use super::{SemverBump, Version, run};
    use std::fs;
    use std::path::Path;

    pub fn has_cargo_toml() -> bool {
        Path::new("Cargo.toml").exists()
    }

    pub fn get_package_name() -> Result<String, String> {
        let cargo_toml_path = "Cargo.toml";
        let content = fs::read_to_string(cargo_toml_path)
            .map_err(|e| format!("Failed to read {cargo_toml_path}: {e}"))?;

        let mut in_package = false;

        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed == "[package]" {
                in_package = true;
            } else if trimmed.starts_with('[') {
                in_package = false;
            } else if in_package && trimmed.starts_with("name") {
                if let Some(start) = line.find('"')
                    && let Some(end) = line.rfind('"')
                {
                    return Ok(line[start + 1..end].to_string());
                }
            }
        }

        Err("Could not find name in [package] section".to_string())
    }

    pub fn get_version() -> Result<Version, String> {
        let cargo_toml_path = "Cargo.toml";
        let content = fs::read_to_string(cargo_toml_path)
            .map_err(|e| format!("Failed to read {cargo_toml_path}: {e}"))?;

        let mut in_package = false;

        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed == "[package]" {
                in_package = true;
            } else if trimmed.starts_with('[') {
                in_package = false;
            } else if in_package && trimmed.starts_with("version") {
                if let Some(start) = line.find('"')
                    && let Some(end) = line.rfind('"')
                {
                    let version_str = &line[start + 1..end];
                    return version_str.parse::<Version>();
                }
            }
        }

        Err("Could not find version in [package] section".to_string())
    }

    /// Update version in Cargo.lock for the local package (package without source field).
    /// This is used in --fast mode to avoid cargo regenerating the lock file on next run.
    pub fn update_cargo_lock_version(
        package_name: &str,
        old_version: &Version,
        new_version: &Version,
    ) -> Result<(), String> {
        let cargo_lock_path = "Cargo.lock";
        if !Path::new(cargo_lock_path).exists() {
            // No Cargo.lock, nothing to update
            return Ok(());
        }

        let content = fs::read_to_string(cargo_lock_path)
            .map_err(|e| format!("Failed to read {cargo_lock_path}: {e}"))?;

        let old_version_str = old_version.to_string();
        let new_version_str = new_version.to_string();

        // Parse Cargo.lock to find the correct package section.
        // We need to find a [[package]] with matching name and version,
        // that does NOT have a source field (local packages have no source).
        let mut result = String::new();
        let mut lines = content.lines().peekable();

        while let Some(line) = lines.next() {
            if line == "[[package]]" {
                // Collect entire package block
                let mut block = vec![line.to_string()];
                while let Some(next_line) = lines.peek() {
                    if next_line.is_empty() || next_line.starts_with("[[") {
                        break;
                    }
                    block.push(lines.next().unwrap().to_string());
                }

                // Check if this is our package (name matches, no source, old version)
                let has_matching_name = block.iter().any(|l| {
                    l.starts_with("name = ")
                        && l.contains(&format!("\"{package_name}\""))
                });
                let has_source = block.iter().any(|l| l.starts_with("source = "));
                let has_old_version = block.iter().any(|l| {
                    l.starts_with("version = ")
                        && l.contains(&format!("\"{old_version_str}\""))
                });

                if has_matching_name && !has_source && has_old_version {
                    // Replace version in this block
                    for block_line in &block {
                        if block_line.starts_with("version = ") {
                            result.push_str(&format!("version = \"{new_version_str}\"\n"));
                        } else {
                            result.push_str(block_line);
                            result.push('\n');
                        }
                    }
                } else {
                    // Keep block as-is
                    for block_line in &block {
                        result.push_str(block_line);
                        result.push('\n');
                    }
                }
            } else {
                result.push_str(line);
                result.push('\n');
            }
        }

        // Remove trailing newline if original didn't have one
        if !content.ends_with('\n') && result.ends_with('\n') {
            result.pop();
        }

        fs::write(cargo_lock_path, result)
            .map_err(|e| format!("Failed to write {cargo_lock_path}: {e}"))?;

        Ok(())
    }

    pub fn bump_version(bump: SemverBump, fast_mode: bool) -> Result<Version, String> {
        let old_version = get_version()?;
        let new_version = match bump {
            SemverBump::Major => old_version.bump_major(),
            SemverBump::Minor => old_version.bump_minor(),
            SemverBump::Patch => old_version.bump_patch(),
        };

        let cargo_toml_path = "Cargo.toml";
        let content = fs::read_to_string(cargo_toml_path)
            .map_err(|e| format!("Failed to read {cargo_toml_path}: {e}"))?;

        let old_version_str = old_version.to_string();
        let new_version_str = new_version.to_string();
        let new_content = content.replacen(&old_version_str, &new_version_str, 1);

        fs::write(cargo_toml_path, new_content)
            .map_err(|e| format!("Failed to write {cargo_toml_path}: {e}"))?;

        // In fast mode, also update Cargo.lock to avoid diffs on next run
        if fast_mode {
            if let Ok(package_name) = get_package_name() {
                if let Err(e) = update_cargo_lock_version(&package_name, &old_version, &new_version)
                {
                    eprintln!("warning: failed to update Cargo.lock: {e}");
                }
            }
        }

        println!("Bumped version: {old_version} -> {new_version}");
        Ok(new_version)
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

    // Error early if -v provided for Rust project
    if args.version.is_some() && is_rust {
        eprintln!("error: -v flag cannot be used in Rust projects, version is defined in Cargo.toml");
        exit(1);
    }

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

    // Determine effective semver bump from flags
    let effective_semver = if args.patch {
        Some(SemverBump::Patch)
    } else if args.major {
        Some(SemverBump::Major)
    } else if args.minor {
        Some(SemverBump::Minor)
    } else {
        None
    };

    // Step 1: Determine the current version BEFORE any modifications
    // For Rust projects: from Cargo.toml
    // For non-Rust projects: from git tags (if using bump flags) or explicit -v flag
    let current_version: Option<Version> = if is_rust {
        match rust::get_version() {
            Ok(v) => Some(v),
            Err(e) => {
                eprintln!("warning: could not read version from Cargo.toml: {e}");
                None
            }
        }
    } else if let Some(v) = args.version {
        // Non-Rust with explicit -v flag
        if let Some(latest) = get_latest_tag() {
            if v < latest {
                eprintln!("error: version v{v} is smaller than the latest tag v{latest}");
                exit(1);
            } else if v == latest {
                eprintln!("warning: version v{v} is the same as the latest tag");
            }
        }
        Some(v)
    } else if effective_semver.is_some() {
        // Non-Rust with bump flags: need existing tag to bump from
        match get_latest_tag() {
            Some(v) => Some(v),
            None => {
                eprintln!("error: no existing version tags found, cannot bump. Use -v to set an initial version.");
                exit(1);
            }
        }
    } else {
        // Non-Rust without version info: try to get from tags
        get_latest_tag()
    };

    // Commit message: user-provided or will be set if version bump happens
    let mut commit_message = args.commit_message.clone();

    // Track the version to use for tagging (may be bumped from current_version)
    // For Rust projects with bump: bump Cargo.toml FIRST, before any git operations
    let release_version: Option<Version> = if is_rust {
        if let Some(bump) = effective_semver {
            match rust::bump_version(bump, args.fast) {
                Ok(v) => {
                    // Set default commit message if user didn't provide one
                    if commit_message.is_none() {
                        commit_message = Some("chore: bump version".to_string());
                    }
                    Some(v)
                }
                Err(e) => {
                    eprintln!("error bumping version: {e}");
                    exit(1);
                }
            }
        } else {
            // No bump requested, use current version from Cargo.toml
            current_version
        }
    } else if let Some(bump) = effective_semver {
        // Non-Rust with bump flags
        let base = current_version.expect("current_version should be set for non-Rust with bump flags");
        let new_version = match bump {
            SemverBump::Patch => base.bump_patch(),
            SemverBump::Minor => base.bump_minor(),
            SemverBump::Major => base.bump_major(),
        };
        println!("Bumping version: v{base} -> v{new_version}");
        Some(new_version)
    } else {
        // Non-Rust without bump: use explicit -v or latest tag
        current_version
    };

    // If we have changes to commit (version bump or user-provided message)
    // Note: version bump ALREADY happened above, so Cargo.toml is modified on disk
    if let Some(ref msg) = commit_message {
        // Stage all files (including untracked) and commit
        if !run("git", &["add", "-A"]) {
            eprintln!("error: git add failed");
            exit(1);
        }
        let _ = run("git", &["commit", "-m", msg]);

        // Push commit to default branch (AFTER commit includes version bump)
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

    // If version determined, tag and push to version branches
    if let Some(version) = release_version {
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
    } else {
        eprintln!("warning: no semver version available, only pushed to 'release' branch");
        eprintln!("hint: for Rust projects, ensure Cargo.toml has a valid version field");
        eprintln!("hint: for other projects, use -v to set a version or --patch/--minor/--major to bump from existing tags");
    }

    println!("Release pushed successfully!");
}
