#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::Parser;
use std::{
    collections::BTreeSet,
    env, fs, io,
    path::{Path, PathBuf},
    process::Command,
    thread,
};

/// Clean cargo projects concurrently. Each path may point anywhere inside a project (root, member, `target/`, `tmp/`, ...) or at a standalone target dir.
/// Project's `tmp/` is nuked too, if it's at least `--tmp-min-gb`.
#[derive(Parser, Debug)]
struct Args {
    #[arg(required = true)]
    paths: Vec<String>,
    #[arg(long, default_value_t = 1.0)]
    tmp_min_gb: f64,
}

#[derive(Debug, PartialEq, Eq, PartialOrd, Ord)]
enum Job {
    Project(PathBuf),
    TargetDir(PathBuf),
}

fn expand(p: &str) -> PathBuf {
    match p.strip_prefix('~') {
        Some(rest) if rest.is_empty() || rest.starts_with('/') => PathBuf::from(format!("{}{rest}", env::var("HOME").expect("HOME is always set in a login env"))),
        _ => PathBuf::from(p),
    }
}

fn resolve(raw: &str) -> Result<Job, String> {
    let path = expand(raw).canonicalize().map_err(|e| format!("{raw}: {e}"))?;
    let out = Command::new("cargo")
        .args(["locate-project", "--workspace", "--message-format", "plain"])
        .current_dir(&path)
        .output()
        .map_err(|e| format!("{raw}: spawning cargo: {e}"))?;
    if out.status.success() {
        let manifest = PathBuf::from(String::from_utf8(out.stdout).expect("cargo prints utf8 paths").trim());
        return Ok(Job::Project(manifest.parent().expect("manifest is a file").to_owned()));
    }
    if path.join("CACHEDIR.TAG").is_file() {
        return Ok(Job::TargetDir(path)); // cargo marks every target dir with it
    }
    Err(format!("{raw}: neither inside a cargo project nor a target dir: {}", String::from_utf8_lossy(&out.stderr).trim()))
}

/// Already-absent counts as removed: the goal is the dir not existing.
fn remove(dir: &Path) -> io::Result<()> {
    match fs::remove_dir_all(dir) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
        r => r,
    }
}

fn size(p: &Path) -> io::Result<u64> {
    let meta = fs::symlink_metadata(p)?;
    if !meta.is_dir() {
        return Ok(meta.len());
    }
    fs::read_dir(p)?.map(|e| size(&e?.path())).sum()
}

fn run(job: &Job, tmp_min: u64) -> Result<(), String> {
    match job {
        Job::TargetDir(t) => remove(t).map_err(|e| format!("{}: {e}", t.display())),
        Job::Project(root) => {
            if !Command::new("cargo").arg("clean").current_dir(root).status().is_ok_and(|s| s.success()) {
                let target = root.join("target");
                remove(&target).map_err(|e| format!("{}: {e}", target.display()))?;
                eprintln!("cargo clean failed for {}; removed {} directly", root.display(), target.display());
            }
            let tmp = root.join("tmp");
            if tmp.is_dir() {
                let bytes = size(&tmp).map_err(|e| format!("{}: {e}", tmp.display()))?;
                if bytes >= tmp_min {
                    remove(&tmp).map_err(|e| format!("{}: {e}", tmp.display()))?;
                    eprintln!("     Removed {} ({:.1}GiB)", tmp.display(), bytes as f64 / (1u64 << 30) as f64);
                }
            }
            Ok(())
        }
    }
}

fn main() {
    let args = Args::parse();
    let tmp_min = (args.tmp_min_gb * (1u64 << 30) as f64) as u64;
    let (jobs, mut failed): (BTreeSet<Job>, Vec<String>) = args.paths.iter().map(|p| resolve(p)).fold((BTreeSet::new(), Vec::new()), |(mut j, mut f), r| {
        match r {
            Ok(job) => _ = j.insert(job),
            Err(e) => f.push(e),
        }
        (j, f)
    });
    failed.extend(thread::scope(|s| {
        let handles: Vec<_> = jobs.iter().map(|j| s.spawn(|| run(j, tmp_min))).collect();
        handles.into_iter().filter_map(|h| h.join().expect("run doesn't panic").err()).collect::<Vec<_>>()
    }));
    if !failed.is_empty() {
        eprintln!("\nFailed to clean:");
        for f in &failed {
            eprintln!("  {f}");
        }
        std::process::exit(1);
    }
}
