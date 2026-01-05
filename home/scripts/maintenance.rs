#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
walkdir = "2"
---

use clap::Parser;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use walkdir::WalkDir;

/// System maintenance script
#[derive(Parser, Debug)]
#[command(name = "maintenance")]
#[command(about = "System maintenance: clean old build artefacts, check caches, refresh nightly version cache, and rebuild NixOS")]
struct Args {
    /// Skip the NixOS rebuild step
    #[arg(long)]
    skip_rebuild: bool,

    /// Only run specific tasks (comma-separated: clean,cache,nightly,rebuild)
    #[arg(long)]
    only: Option<String>,
}

const FOUR_WEEKS_SECS: u64 = 4 * 7 * 24 * 3600;
const HOME_CACHE_THRESHOLD_KB: u64 = 20_000_000; // 20GB

fn main() {
    let args = Args::parse();

    let tasks: Vec<&str> = if let Some(ref only) = args.only {
        only.split(',').collect()
    } else {
        vec!["clean", "cache", "nightly", "rebuild"]
    };

    let mut handles = vec![];

    if tasks.contains(&"clean") {
        handles.push(std::thread::spawn(|| {
            if clean_old_build_artefacts() {
                println!("\x1b[32mChecked for old build artefacts\x1b[0m");
            } else {
                eprintln!("\x1b[31mFailed to check for old build artefacts\x1b[0m");
            }
        }));
    }

    if tasks.contains(&"cache") {
        handles.push(std::thread::spawn(|| {
            if check_caches() {
                println!("\x1b[32mChecked caches\x1b[0m");
            } else {
                eprintln!("\x1b[31mFailed to check caches\x1b[0m");
            }
        }));
    }

    if tasks.contains(&"nightly") {
        handles.push(std::thread::spawn(|| {
            let status = Command::new("fish")
                .args(["-c", "check_nightly_versions --discover"])
                .status();
            if status.map(|s| s.success()).unwrap_or(false) {
                println!("\x1b[32mRefreshed nightly version file cache\x1b[0m");
            } else {
                eprintln!("\x1b[31mFailed to refresh nightly version cache\x1b[0m");
            }
        }));
    }

    for handle in handles {
        let _ = handle.join();
    }

    // Record maintenance run timestamp
    let state_dir = std::env::var("XDG_STATE_HOME")
        .unwrap_or_else(|_| format!("{}/.local/state", std::env::var("HOME").unwrap()));
    let fish_state_dir = PathBuf::from(&state_dir).join("fish");
    let _ = fs::create_dir_all(&fish_state_dir);
    let timestamp_file = fish_state_dir.join("maintenance_last_run");
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let _ = fs::write(&timestamp_file, now.to_string());

    if tasks.contains(&"rebuild") && !args.skip_rebuild {
        let nixos_config = std::env::var("NIXOS_CONFIG")
            .unwrap_or_else(|_| "/home/v/nix".to_string());

        let rebuild_status = Command::new("sudo")
            .args(["nixos-rebuild", "switch", "--show-trace", "-v", "--impure"])
            .status();

        if rebuild_status.map(|s| s.success()).unwrap_or(false) {
            // Git commit on successful build
            let _ = Command::new("git")
                .args(["-C", &nixos_config, "add", "-A"])
                .status();
            let _ = Command::new("git")
                .args(["-C", &nixos_config, "commit", "-m", "_"])
                .status();
            let _ = Command::new("git")
                .args(["-C", &nixos_config, "push"])
                .status();
        }
    }
}

fn clean_old_build_artefacts() -> bool {
    let directories = [
        "/home/v/tmp/",
        "/home/v/s/",
        "/home/v/g/",
        "/home/v/leetcode/",
        "/home/v/uni/",
    ];

    println!("\x1b[34mCleaning old build artefacts\x1b[0m");

    for dir in directories {
        let path = Path::new(dir);
        if !path.exists() {
            eprintln!("\x1b[31mDirectory {} does not exist\x1b[0m", dir);
            continue;
        }

        println!("Searching for stale projects in: \x1b[34m{}\x1b[0m", dir);

        for entry in WalkDir::new(dir)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name() == "Cargo.toml")
        {
            let parent_dir = entry.path().parent().unwrap();
            let target_dir = parent_dir.join("target");

            if target_dir.exists() {
                if let Ok(metadata) = fs::metadata(parent_dir) {
                    if let Ok(modified) = metadata.modified() {
                        if let Ok(elapsed) = modified.elapsed() {
                            if elapsed > Duration::from_secs(FOUR_WEEKS_SECS) {
                                println!("\x1b[32mCleaned build artefacts in: {}\x1b[0m", parent_dir.display());
                                let _ = Command::new("cargo")
                                    .arg("clean")
                                    .current_dir(parent_dir)
                                    .status();
                            }
                        }
                    }
                }
            }
        }
    }

    true
}

fn check_caches() -> bool {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/home/v".to_string());
    let cache_dir = PathBuf::from(&home).join(".cache");

    // Get cache size in KB using du
    let output = Command::new("du")
        .args(["-sk", cache_dir.to_str().unwrap()])
        .output();

    if let Ok(output) = output {
        let output_str = String::from_utf8_lossy(&output.stdout);
        if let Some(size_str) = output_str.split_whitespace().next() {
            if let Ok(size_kb) = size_str.parse::<u64>() {
                if size_kb > HOME_CACHE_THRESHOLD_KB {
                    println!("\x1b[34mHome cache is {}GB, cleaning...\x1b[0m", size_kb / 1_000_000);
                    if let Ok(entries) = fs::read_dir(&cache_dir) {
                        for entry in entries.flatten() {
                            let _ = fs::remove_dir_all(entry.path());
                        }
                    }
                    println!("\x1b[32mCleaned home cache\x1b[0m");
                }
            }
        }
    }

    true
}
