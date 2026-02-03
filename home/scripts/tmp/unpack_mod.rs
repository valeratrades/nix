#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
dirs = "5"
zip = "2"
---

use clap::{Parser, Subcommand};
use std::fs::{self, File};
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Manage Factorio mods
#[derive(Parser, Debug)]
#[command(name = "unpack_mod")]
#[command(about = "Manage Factorio mods")]
struct Args {
    /// Path to Factorio directory or any child thereof
    #[arg(short, long, required = true)]
    path: PathBuf,

    #[command(subcommand)]
    command: Option<Cmd>,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Unpack newest zip files from ~/Downloads
    Downloads {
        /// Number of newest zip files to unpack, or "all"
        #[arg(short, long, default_value = "1")]
        number: String,
    },
    /// Install a mod from a GitHub repository
    FromGithub {
        /// GitHub repository URL (e.g., https://github.com/user/repo)
        url: String,
    },
}

fn find_factorio_root(path: &Path) -> Result<PathBuf, String> {
    let canonical = path
        .canonicalize()
        .map_err(|e| format!("Invalid path '{}': {e}", path.display()))?;

    // Check $path/factorio/ first
    let factorio_subdir = canonical.join("factorio");
    if factorio_subdir.join("factorio-current.log").exists() {
        return Ok(factorio_subdir);
    }

    // Then walk up parents
    let mut current = canonical.as_path();
    loop {
        if current.join("factorio-current.log").exists() {
            return Ok(current.to_path_buf());
        }
        current = match current.parent() {
            Some(p) => p,
            None => break,
        };
    }

    Err(format!(
        "Could not find Factorio root from '{}'. \
        Expected to find 'factorio-current.log' in the directory or any parent.\n\
        Factorio root typically looks like:\n  \
        achievements.dat  config  data  factorio-current.log  mods  saves  ...",
        path.display()
    ))
}

fn get_zip_files_sorted_by_ctime(downloads_dir: &Path) -> io::Result<Vec<PathBuf>> {
    let mut zips: Vec<(PathBuf, std::time::SystemTime)> = fs::read_dir(downloads_dir)?
        .filter_map(|entry| {
            let entry = entry.ok()?;
            let path = entry.path();
            if path.extension().is_some_and(|ext| ext == "zip") {
                let metadata = entry.metadata().ok()?;
                let ctime = metadata.created().or_else(|_| metadata.modified()).ok()?;
                Some((path, ctime))
            } else {
                None
            }
        })
        .collect();

    zips.sort_by(|a, b| b.1.cmp(&a.1));
    Ok(zips.into_iter().map(|(p, _)| p).collect())
}

fn get_zip_top_level_dir(zip_path: &Path) -> Result<String, String> {
    let file = File::open(zip_path)
        .map_err(|e| format!("Failed to open '{}': {e}", zip_path.display()))?;
    let mut archive = zip::ZipArchive::new(file)
        .map_err(|e| format!("Failed to read zip '{}': {e}", zip_path.display()))?;

    for i in 0..archive.len() {
        let file = archive
            .by_index(i)
            .map_err(|e| format!("Failed to read entry {i}: {e}"))?;
        let path = file.mangled_name();
        if let Some(first_component) = path.components().next() {
            return Ok(first_component.as_os_str().to_string_lossy().to_string());
        }
    }

    Err("Zip archive is empty".to_string())
}

fn unpack_zip_to_mods(zip_path: &Path, mods_dir: &Path) -> Result<(), String> {
    let file = File::open(zip_path)
        .map_err(|e| format!("Failed to open '{}': {e}", zip_path.display()))?;
    let mut archive = zip::ZipArchive::new(file)
        .map_err(|e| format!("Failed to read zip '{}': {e}", zip_path.display()))?;

    for i in 0..archive.len() {
        let mut file = archive
            .by_index(i)
            .map_err(|e| format!("Failed to read entry {i}: {e}"))?;
        let outpath = mods_dir.join(file.mangled_name());

        if file.is_dir() {
            fs::create_dir_all(&outpath)
                .map_err(|e| format!("Failed to create dir '{}': {e}", outpath.display()))?;
        } else {
            if let Some(parent) = outpath.parent() {
                fs::create_dir_all(parent).map_err(|e| {
                    format!("Failed to create parent dir '{}': {e}", parent.display())
                })?;
            }
            let mut outfile = File::create(&outpath)
                .map_err(|e| format!("Failed to create file '{}': {e}", outpath.display()))?;
            io::copy(&mut file, &mut outfile)
                .map_err(|e| format!("Failed to write '{}': {e}", outpath.display()))?;
        }
    }

    Ok(())
}

fn copy_dir_all(src: &Path, dst: &Path) -> Result<(), String> {
    fs::create_dir_all(dst)
        .map_err(|e| format!("Failed to create dir '{}': {e}", dst.display()))?;
    for entry in
        fs::read_dir(src).map_err(|e| format!("Failed to read dir '{}': {e}", src.display()))?
    {
        let entry = entry.map_err(|e| format!("Failed to read entry: {e}"))?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        if src_path.is_dir() {
            copy_dir_all(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path)
                .map_err(|e| format!("Failed to copy '{}': {e}", src_path.display()))?;
        }
    }
    Ok(())
}

fn parse_github_url(url: &str) -> Result<(String, String), String> {
    // Accept: https://github.com/user/repo or https://github.com/user/repo/
    let url = url.trim_end_matches('/');
    let prefix = "https://github.com/";
    if !url.starts_with(prefix) {
        return Err(format!("URL must start with {prefix}"));
    }
    let rest = &url[prefix.len()..];
    let parts: Vec<&str> = rest.split('/').collect();
    if parts.len() < 2 {
        return Err("URL must be in format https://github.com/user/repo".to_string());
    }
    Ok((parts[0].to_string(), parts[1].to_string()))
}

fn install_from_github(url: &str, mods_dir: &Path) -> Result<(), String> {
    let (user, repo) = parse_github_url(url)?;

    let tmp_dir = std::env::temp_dir().join(format!("factorio-mod-{}-{}", user, repo));
    if tmp_dir.exists() {
        fs::remove_dir_all(&tmp_dir).map_err(|e| format!("Failed to clean temp dir: {e}"))?;
    }

    println!("Cloning {user}/{repo}...");
    let status = Command::new("git")
        .args(["clone", "--depth=1", url, tmp_dir.to_str().unwrap()])
        .status()
        .map_err(|e| format!("Failed to run git: {e}"))?;

    if !status.success() {
        return Err("git clone failed".to_string());
    }

    // Find mod name from info.json
    let info_json = tmp_dir.join("info.json");
    if !info_json.exists() {
        fs::remove_dir_all(&tmp_dir).ok();
        return Err("No info.json found in repository root - not a valid Factorio mod".to_string());
    }

    let info_content =
        fs::read_to_string(&info_json).map_err(|e| format!("Failed to read info.json: {e}"))?;

    // Simple JSON parsing for "name" field
    let mod_name = info_content
        .lines()
        .find(|line| line.contains("\"name\""))
        .and_then(|line| {
            let start = line.find('"')? + 1;
            let rest = &line[start..];
            let end = rest.find('"')?;
            let rest = &rest[end + 1..];
            let start = rest.find('"')? + 1;
            let rest = &rest[start..];
            let end = rest.find('"')?;
            Some(rest[..end].to_string())
        })
        .ok_or("Failed to parse mod name from info.json")?;

    // Remove .git directory
    let git_dir = tmp_dir.join(".git");
    if git_dir.exists() {
        fs::remove_dir_all(&git_dir).map_err(|e| format!("Failed to remove .git: {e}"))?;
    }

    let dest = mods_dir.join(&mod_name);
    if dest.exists() {
        fs::remove_dir_all(&tmp_dir).ok();
        return Err(format!(
            "Mod '{}' already installed at {}",
            mod_name,
            dest.display()
        ));
    }

    println!("Installing {} to {}...", mod_name, dest.display());
    // Use copy + remove instead of rename to handle cross-device moves
    copy_dir_all(&tmp_dir, &dest)?;
    fs::remove_dir_all(&tmp_dir).map_err(|e| format!("Failed to clean up temp dir: {e}"))?;

    println!("Done.");
    Ok(())
}

fn cmd_downloads(mods_dir: &Path, number: &str) {
    let downloads_dir = dirs::home_dir()
        .map(|h| h.join("Downloads"))
        .filter(|d| d.exists())
        .unwrap_or_else(|| {
            eprintln!("Error: ~/Downloads directory not found");
            std::process::exit(1);
        });

    let zip_files = match get_zip_files_sorted_by_ctime(&downloads_dir) {
        Ok(files) => files,
        Err(e) => {
            eprintln!("Error reading Downloads directory: {e}");
            std::process::exit(1);
        }
    };

    if zip_files.is_empty() {
        eprintln!("Error: No .zip files found in ~/Downloads");
        std::process::exit(1);
    }

    let count: usize = if number == "all" {
        zip_files.len()
    } else {
        match number.parse::<usize>() {
            Ok(0) => {
                eprintln!("Error: --number must be at least 1");
                std::process::exit(1);
            }
            Ok(n) => n,
            Err(_) => {
                eprintln!("Error: --number must be a positive integer or 'all', got '{number}'");
                std::process::exit(1);
            }
        }
    };

    if count > zip_files.len() {
        eprintln!(
            "Error: requested {count} zip files but only {} found in ~/Downloads",
            zip_files.len()
        );
        std::process::exit(1);
    }

    let to_unpack = &zip_files[..count];

    println!("Unpacking {} zip file(s) to {}", count, mods_dir.display());

    for zip_path in to_unpack {
        let filename = zip_path.file_name().unwrap_or_default().to_string_lossy();
        print!("  {filename} ... ");

        let top_dir = match get_zip_top_level_dir(zip_path) {
            Ok(d) => d,
            Err(e) => {
                println!("FAILED");
                eprintln!("Error: {e}");
                std::process::exit(1);
            }
        };

        let dest = mods_dir.join(&top_dir);
        if dest.exists() {
            println!("SKIPPED (already installed at {})", dest.display());
            continue;
        }

        match unpack_zip_to_mods(zip_path, mods_dir) {
            Ok(()) => {
                if let Err(e) = fs::remove_file(zip_path) {
                    println!("ok (failed to delete: {e})");
                } else {
                    println!("ok (deleted)");
                }
            }
            Err(e) => {
                println!("FAILED");
                eprintln!("Error: {e}");
                std::process::exit(1);
            }
        }
    }

    println!("Done.");
}

fn main() {
    let args = Args::parse();

    let factorio_root = match find_factorio_root(&args.path) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("Error: {e}");
            std::process::exit(1);
        }
    };

    let mods_dir = factorio_root.join("mods");
    if !mods_dir.exists() {
        eprintln!(
            "Error: mods directory not found at '{}'",
            mods_dir.display()
        );
        std::process::exit(1);
    }

    match args.command {
        Some(Cmd::Downloads { number }) => cmd_downloads(&mods_dir, &number),
        Some(Cmd::FromGithub { url }) => {
            if let Err(e) = install_from_github(&url, &mods_dir) {
                eprintln!("Error: {e}");
                std::process::exit(1);
            }
        }
        None => {
            // Default to downloads with number=1 for backward compatibility
            cmd_downloads(&mods_dir, "1");
        }
    }
}
