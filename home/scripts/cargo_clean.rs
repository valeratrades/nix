#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::Parser;
use std::{env, path::PathBuf, process::Command, thread};

/// `cargo clean` each path concurrently; on failure remove its `target/` directly
#[derive(Parser, Debug)]
struct Args {
    #[arg(required = true)]
    paths: Vec<String>,
}

fn expand(p: &str) -> PathBuf {
    match p.strip_prefix('~') {
        Some(rest) if rest.is_empty() || rest.starts_with('/') => PathBuf::from(format!("{}{rest}", env::var("HOME").expect("HOME is always set in a login env"))),
        _ => PathBuf::from(p),
    }
}

fn clean(raw: &str) -> Result<(), String> {
    let path = expand(raw);
    if Command::new("cargo").arg("clean").current_dir(&path).status().is_ok_and(|s| s.success()) {
        return Ok(());
    }
    let target = path.join("target");
    std::fs::remove_dir_all(&target).map_err(|e| format!("{raw}: {e}"))?;
    eprintln!("cargo clean failed for {raw}; removed {} directly", target.display());
    Ok(())
}

fn main() {
    let paths = Args::parse().paths;
    let failed: Vec<String> = thread::scope(|s| {
        let handles: Vec<_> = paths.iter().map(|p| s.spawn(|| clean(p))).collect();
        handles.into_iter().filter_map(|h| h.join().expect("clean doesn't panic").err()).collect()
    });
    if !failed.is_empty() {
        eprintln!("\nFailed to clean:");
        for f in &failed {
            eprintln!("  {f}");
        }
        std::process::exit(1);
    }
}
