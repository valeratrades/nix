#!/usr/bin/env nix
---cargo
#! nix shell --impure --expr ``
#! nix let rust_flake = builtins.getFlake ''github:oxalica/rust-overlay'';
#! nix     nixpkgs_flake = builtins.getFlake ''nixpkgs'';
#! nix     pkgs = import nixpkgs_flake {
#! nix       system = builtins.currentSystem;
#! nix       overlays = [rust_flake.overlays.default];
#! nix     };
#! nix     toolchain = pkgs.rust-bin.nightly."2025-10-10".default.override {
#! nix       extensions = ["rust-src"];
#! nix     };
#! nix
#! nix in toolchain
#! nix ``
#! nix --command sh -c ``cargo -Zscript -q "$0" "$@"``

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
chrono = "0.4"
---

use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};
use chrono::DateTime;
use serde::Serialize;

#[derive(Serialize)]
struct Output {
    main: String,
    additional: String,
}

struct LineConfig {
    name: &'static str,
    file: PathBuf,
    max_age_secs: u64,
}

fn main() {
    let state_dir = dirs::home_dir()
        .expect("Failed to get home directory")
        .join(".local/state/btc_line");

    let lines = vec![
        LineConfig {
            name: "main",
            file: state_dir.join("main"),
            max_age_secs: 60,
        },
        LineConfig {
            name: "additional",
            file: state_dir.join("additional"),
            max_age_secs: 900,
        },
        LineConfig {
            name: "spy",
            file: state_dir.join("spy"),
            max_age_secs: 60,
        },
    ];

    let timestamps_file = state_dir.join(".timestamps");
    let current_time = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("Time went backwards")
        .as_secs();

    // Restore values if needed
    for line in &lines {
        restore_if_needed(line, &timestamps_file, current_time);
    }

    // Check and output main and additional values
    let main_value = get_value_or_none(&lines[0], &timestamps_file, current_time);
    let additional_value = get_value_or_none(&lines[1], &timestamps_file, current_time);

    let output = Output {
        main: main_value,
        additional: additional_value,
    };

    println!("{}", serde_json::to_string(&output).unwrap());
}

fn get_timestamp(timestamps_file: &PathBuf, name: &str) -> Option<u64> {
    let content = fs::read_to_string(timestamps_file).ok()?;

    for line in content.lines() {
        if let Some(rest) = line.strip_prefix(&format!("{}: ", name)) {
            if let Ok(dt) = DateTime::parse_from_rfc3339(rest) {
                return Some(dt.timestamp() as u64);
            }
        }
    }

    None
}

fn read_file(path: &PathBuf) -> Option<String> {
    fs::read_to_string(path)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn restore_if_needed(line: &LineConfig, timestamps_file: &PathBuf, current_time: u64) {
    // Get timestamp and check freshness
    let timestamp = get_timestamp(timestamps_file, line.name).unwrap_or(0);
    let age = current_time.saturating_sub(timestamp);

    // Only proceed if data is fresh enough
    if age <= line.max_age_secs {
        // Check if eww variable is empty
        let eww_var = format!("btc_line_{}_str", line.name);
        let output = Command::new("eww")
            .args(["get", &eww_var])
            .output();

        if let Ok(output) = output {
            let current_value = String::from_utf8_lossy(&output.stdout).trim().to_string();

            // If empty, restore from file
            if current_value.is_empty() {
                if let Some(file_value) = read_file(&line.file) {
                    let _ = Command::new("eww")
                        .args(["update", &format!("{}={}", eww_var, file_value)])
                        .status();
                }
            }
        }
    }
}

fn get_value_or_none(line: &LineConfig, timestamps_file: &PathBuf, current_time: u64) -> String {
    let timestamp = get_timestamp(timestamps_file, line.name).unwrap_or(0);
    let age = current_time.saturating_sub(timestamp);

    if age > line.max_age_secs {
        "None".to_string()
    } else {
        read_file(&line.file).unwrap_or_default()
    }
}

// Simple home_dir implementation since it's deprecated in std
mod dirs {
    use std::path::PathBuf;
    use std::env;

    pub fn home_dir() -> Option<PathBuf> {
        env::var_os("HOME").map(PathBuf::from)
    }
}
