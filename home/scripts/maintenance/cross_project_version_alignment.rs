#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
ignore = "0.4"
regex-lite = "0.1"
---

use clap::{Parser, Subcommand};
use ignore::WalkBuilder;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[derive(Parser, Debug)]
#[command(name = "cross_project_version_alignment")]
#[command(about = "Ensure version alignment across projects")]
struct Args {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Check rust nightly version alignment across scripts
    Rust {
        /// Discovery mode: find and cache all relevant files
        #[arg(long)]
        discover: bool,
        /// Directories to search (only used with --discover, default: ~/s ~/nix/home/scripts)
        #[arg(requires = "discover")]
        dirs: Vec<PathBuf>,
    },
    /// Align lean4 projects to use pinned lean4-nix
    Lean {
        /// Directories to search for lean4 projects
        dirs: Vec<PathBuf>,
    },
}

fn get_state_dir() -> PathBuf {
    std::env::var("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").expect("HOME not set");
            PathBuf::from(home).join(".local/state")
        })
}

// ============================================================================
// Rust nightly version checking
// ============================================================================

fn rust_check(discover: bool, dirs: Vec<PathBuf>) {
    let cache_path = get_state_dir().join("fish/nightly_version_files.txt");

    let dirs = if dirs.is_empty() {
        let home = std::env::var("HOME").expect("HOME not set");
        vec![
            PathBuf::from(&home).join("s"),
            PathBuf::from(&home).join("nix/home/scripts"),
        ]
    } else {
        dirs
    };

    let files_to_check: Vec<PathBuf> = if discover {
        let files = discover_rust_files(&dirs);

        if let Some(parent) = cache_path.parent() {
            fs::create_dir_all(parent).ok();
        }

        let content: String = files
            .iter()
            .map(|p| p.to_string_lossy().to_string())
            .collect::<Vec<_>>()
            .join("\n");
        fs::write(&cache_path, &content).expect("Failed to write cache file");

        println!(
            "Discovered {} files with nightly references, cached to {}",
            files.len(),
            cache_path.display()
        );

        files
    } else {
        if !cache_path.exists() {
            eprintln!("Error: No cached file list. Run with --discover first.");
            std::process::exit(1);
        }

        fs::read_to_string(&cache_path)
            .expect("Failed to read cache file")
            .lines()
            .filter(|l| !l.is_empty())
            .map(PathBuf::from)
            .filter(|p| p.exists())
            .collect()
    };

    check_rust_versions(&files_to_check);
}

const SELECT_LATEST_NIGHTLY: &str = "selectLatestNightlyWith";
const NIGHTLY_PREFIX: &str = "nightly.\"";

fn discover_rust_files(dirs: &[PathBuf]) -> Vec<PathBuf> {
    let mut files = Vec::new();
    let self_name = "cross_project_version_alignment.rs";

    for dir in dirs {
        if !dir.is_dir() {
            eprintln!("Warning: {} is not a directory", dir.display());
            continue;
        }

        for entry in WalkBuilder::new(dir).hidden(false).build().flatten() {
            let path = entry.path();
            if path.extension().map(|e| e == "rs").unwrap_or(false) {
                // Skip self to avoid false positive on pattern strings
                if path.file_name().map(|n| n == self_name).unwrap_or(false) {
                    continue;
                }
                if let Ok(content) = fs::read_to_string(path) {
                    if content.contains(SELECT_LATEST_NIGHTLY) || content.contains(NIGHTLY_PREFIX) {
                        files.push(path.to_path_buf());
                    }
                }
            }
        }
    }

    files
}

fn check_rust_versions(files: &[PathBuf]) {
    let mut has_warning = false;
    let mut versions: Vec<(String, PathBuf)> = Vec::new();

    let date_pattern = regex_lite::Regex::new(r#"nightly\."(\d{4}-\d{2}-\d{2})""#).unwrap();

    for file in files {
        let content = match fs::read_to_string(file) {
            Ok(c) => c,
            Err(_) => continue,
        };

        if content.contains(SELECT_LATEST_NIGHTLY) {
            eprintln!(
                "Warning: {} uses selectLatestNightlyWith instead of pinned nightly version",
                file.display()
            );
            has_warning = true;
        }

        if let Some(caps) = date_pattern.captures(&content) {
            if let Some(m) = caps.get(1) {
                versions.push((m.as_str().to_string(), file.clone()));
            }
        }
    }

    if !versions.is_empty() {
        let first_version = &versions[0].0;

        for (version, file) in &versions {
            if version != first_version {
                eprintln!(
                    "Warning: {} uses nightly version {} (expected {})",
                    file.display(),
                    version,
                    first_version
                );
                has_warning = true;
            }
        }
    }

    if has_warning {
        std::process::exit(1);
    }
}

// ============================================================================
// Lean4 version alignment
// ============================================================================

const LEAN_NIX_PIN: &str =
    r#"= "github:lenianiva/lean4-nix/ecaa70749083e6a0e6e0814c6a66b7561754b6db"; # pinned 2026-01-10"#;
const ENVRC_CONTENT: &str = "use flake . --profile .direnv/flake-profile\n";

fn lean_align(dirs: Vec<PathBuf>) {
    if dirs.is_empty() {
        eprintln!("Error: No directories specified for lean alignment");
        std::process::exit(1);
    }

    for dir in &dirs {
        if !dir.is_dir() {
            eprintln!("Warning: {} is not a directory", dir.display());
            continue;
        }

        for entry in WalkBuilder::new(dir).hidden(false).build().flatten() {
            let path = entry.path();
            if path.file_name().map(|n| n == "lake-manifest.json").unwrap_or(false) {
                let project_dir = path.parent().unwrap();
                process_lean_project(project_dir);
            }
        }
    }
}

fn process_lean_project(project_dir: &Path) {
    let project_name = project_dir
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| project_dir.to_string_lossy().to_string());

    let envrc_path = project_dir.join(".envrc");
    let flake_path = project_dir.join("flake.nix");

    // Check if .envrc exists
    if !envrc_path.exists() {
        println!("{}: skipping (no .envrc - likely unpatched clone)", project_name);
        return;
    }

    let mut updates_made = false;

    // Check and update .envrc
    let envrc_content = fs::read_to_string(&envrc_path).unwrap_or_default();
    if envrc_content.trim() != ENVRC_CONTENT.trim() {
        fs::write(&envrc_path, ENVRC_CONTENT).expect("Failed to write .envrc");
        updates_made = true;
    }

    // Check and update flake.nix
    if flake_path.exists() {
        let flake_content = fs::read_to_string(&flake_path).expect("Failed to read flake.nix");

        if let Some(updated) = update_lean_nix_input(&flake_content) {
            fs::write(&flake_path, updated).expect("Failed to write flake.nix");
            updates_made = true;
        }
    }

    if updates_made {
        println!("{}: updated", project_name);

        // Run direnv allow to apply changes
        let _ = Command::new("direnv")
            .args(["allow", project_dir.to_str().unwrap()])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    } else {
        println!("{}: already aligned", project_name);
    }
}

fn update_lean_nix_input(content: &str) -> Option<String> {
    let mut result = String::new();
    let mut modified = false;

    for line in content.lines() {
        if line.contains("lenianiva/") {
            // Find the part before '=' and reconstruct the line
            if let Some(eq_pos) = line.find('=') {
                let prefix = &line[..eq_pos];
                let new_line = format!("{}{}", prefix, LEAN_NIX_PIN);

                if line.trim() != new_line.trim() {
                    result.push_str(&new_line);
                    result.push('\n');
                    modified = true;
                    continue;
                }
            }
        }
        result.push_str(line);
        result.push('\n');
    }

    // Remove trailing newline if original didn't have one
    if !content.ends_with('\n') && result.ends_with('\n') {
        result.pop();
    }

    if modified {
        Some(result)
    } else {
        None
    }
}

fn main() {
    let args = Args::parse();

    match args.command {
        Commands::Rust { discover, dirs } => rust_check(discover, dirs),
        Commands::Lean { dirs } => lean_align(dirs),
    }
}
