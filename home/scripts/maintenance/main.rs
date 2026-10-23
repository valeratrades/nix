#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
walkdir = "2"
---

use clap::Parser;
use serde::Deserialize;
use std::fmt::Display;
use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};
use walkdir::WalkDir;

/// System maintenance script
#[derive(Parser, Debug)]
#[command(name = "maintenance")]
#[command(about = "System maintenance: clean outdated ~/tmp, ~/.cache and build artefacts, refresh nightly version cache, and rebuild NixOS")]
struct Args {
    /// Skip the NixOS rebuild step
    #[arg(long)]
    skip_rebuild: bool,

    /// Only run specific tasks (comma-separated: clean,cache,nightly,shadows,rebuild)
    #[arg(long)]
    only: Option<String>,

    /// Report what would be removed, then stop before touching anything
    #[arg(long)]
    dry_run: bool,
}

/// written by home-manager from ./config.nix
#[derive(Deserialize)]
struct Config {
    outdated_after_days: u64,
    unit_markers: Vec<String>,
    cache_limit_gb: u64,
}

struct Ctx {
    cfg: Config,
    home: PathBuf,
    log: PathBuf,
    dry_run: bool,
}

struct Unit {
    path: PathBuf,
    last_use: SystemTime,
    bytes: u64,
}

fn env(key: &str) -> String {
    std::env::var(key).unwrap_or_else(|e| panic!("${key}: {e}"))
}

fn main() {
    let args = Args::parse();
    let state = PathBuf::from(env("XDG_STATE_HOME"));
    let config_path = PathBuf::from(env("XDG_CONFIG_HOME")).join("maintenance/config.json");
    let config = fs::read_to_string(&config_path).unwrap_or_else(|e| panic!("{}: {e}", config_path.display()));
    fs::create_dir_all(state.join("maintenance")).expect("state dir is ours to create");
    let ctx = Ctx {
        cfg: serde_json::from_str(&config).unwrap_or_else(|e| panic!("{}: {e}", config_path.display())),
        home: PathBuf::from(env("HOME")),
        log: state.join("maintenance/log"),
        dry_run: args.dry_run,
    };

    let tasks: Vec<&str> = match args.only {
        Some(ref only) => only.split(',').collect(),
        None => vec!["clean", "cache", "nightly", "shadows", "rebuild"],
    };

    std::thread::scope(|s| {
        if tasks.contains(&"clean") {
            s.spawn(|| {
                ctx.sweep(&ctx.home.join("tmp"), None); // before artefact cleaning, which also walks ~/tmp
                ctx.clean_old_build_artefacts();
            });
        }
        if tasks.contains(&"cache") {
            s.spawn(|| ctx.sweep(&ctx.home.join(".cache"), Some(ctx.cfg.cache_limit_gb << 30)));
        }
        if tasks.contains(&"nightly") {
            s.spawn(|| {
                let script = "/home/v/nix/home/scripts/maintenance/cross_project_version_alignment.rs";
                if ctx.run(Command::new(script).args(["rust", "--discover"])) {
                    ctx.report(false, "Refreshed nightly version file cache");
                }
            });
        }
        if tasks.contains(&"shadows") {
            s.spawn(|| ctx.check_cargo_nix_shadows());
        }
    });

    if args.dry_run {
        return;
    }

    let fish_state_dir = state.join("fish");
    fs::create_dir_all(&fish_state_dir).expect("state dir is ours to create");
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    fs::write(fish_state_dir.join("maintenance_last_run"), now.to_string()).expect("dir created above");

    if tasks.contains(&"rebuild") && !args.skip_rebuild {
        let nixos_config = env("NIXOS_CONFIG");
        let hostname = String::from_utf8_lossy(&Command::new("hostname").output().expect("Failed to get hostname").stdout)
            .trim()
            .to_string();
        let git = || {
            let mut git = Command::new("git");
            git.arg("-C").arg(&nixos_config);
            git
        };

        let rebuilt = ctx.run(Command::new("sudo").args([
            "nixos-rebuild",
            "switch",
            "--impure",
            "--no-reexec",
            "--flake",
            &format!("{}#{}", nixos_config, hostname),
            "--show-trace",
            "-v",
        ]));
        if rebuilt && ctx.run(git().args(["add", "-A"])) {
            match git().args(["diff", "--cached", "--quiet"]).status().map(|s| s.code()) {
                Ok(Some(0)) => {}
                Ok(Some(1)) => _ = ctx.run(git().args(["commit", "-m", "_"])),
                other => ctx.report(true, format_args!("git diff --cached: {other:?}")),
            }
            ctx.run(git().arg("push"));
        }
    }

    println!("\n\x1b[34m═══ Shell Startup Profile ═══\x1b[0m\n");
    let status = Command::new("/home/v/nix/scripts/profile_shell.rs")
        .args(["startup", "--runs", "3"])
        .status()
        .expect("script is in the repo");
    assert!(status.success(), "profile_shell.rs: {status}");
}

impl Ctx {
    /// printed, and appended to the log so removals stay traceable after the terminal is gone
    fn report(&self, err: bool, msg: impl Display) {
        match err {
            true => eprintln!("\x1b[31m{msg}\x1b[0m"),
            false => println!("\x1b[32m{msg}\x1b[0m"),
        }
        let secs = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
        let mut log = fs::OpenOptions::new().create(true).append(true).open(&self.log).unwrap_or_else(|e| panic!("{}: {e}", self.log.display()));
        let line = format!("{secs} {} {msg}\n", if err { "ERR" } else { "ok " }); // one write, so O_APPEND keeps threads' lines whole
        log.write_all(line.as_bytes()).unwrap_or_else(|e| panic!("{}: {e}", self.log.display()));
    }

    fn run(&self, cmd: &mut Command) -> bool {
        match cmd.status() {
            Ok(s) if s.success() => true,
            Ok(s) => {
                self.report(true, format_args!("{cmd:?}: {s}"));
                false
            }
            Err(e) => {
                self.report(true, format_args!("{cmd:?}: {e}"));
                false
            }
        }
    }

    fn unused_days(&self, last_use: SystemTime) -> Option<u64> {
        let days = last_use.elapsed().map_or(0, |e| e.as_secs() / 86400); // Err: last use is in the future, so in use
        (days >= self.cfg.outdated_after_days).then_some(days)
    }

    fn remove(&self, path: &Path, why: impl Display) {
        assert!(path.starts_with(&self.home) && path != self.home, "{} is outside $HOME", path.display());
        if self.dry_run {
            return self.report(false, format_args!("would remove {} ({why})", path.display()));
        }
        let removed = fs::symlink_metadata(path).and_then(|m| if m.is_dir() { fs::remove_dir_all(path) } else { fs::remove_file(path) });
        match removed {
            Ok(()) => self.report(false, format_args!("removed {} ({why})", path.display())),
            Err(e) => self.report(true, format_args!("failed to remove {}: {e}", path.display())),
        }
    }

    /// Removes outdated units under `root`, then with a `limit` (bytes) the least recently used ones until the rest fits.
    fn sweep(&self, root: &Path, limit: Option<u64>) {
        println!("\x1b[34mSweeping {} for units unused for {} days\x1b[0m", root.display(), self.cfg.outdated_after_days);
        let (mut units, mut dirs) = (vec![], vec![]);
        self.collect(root, &mut units, &mut dirs);
        units.sort_by_key(|u| u.last_use);
        let mut kept: u64 = units.iter().map(|u| u.bytes).sum();
        for unit in &units {
            let days = self.unused_days(unit.last_use);
            let over_limit = limit.is_some_and(|limit| kept > limit);
            if days.is_none() && !over_limit {
                break; // sorted: everything after is fresher
            }
            let why = match days {
                Some(days) => format!("unused {days}d"),
                None => format!("~/.cache over {}GB", self.cfg.cache_limit_gb),
            };
            self.remove(&unit.path, why);
            kept -= unit.bytes;
        }
        for (dir, mtime) in dirs.iter().rev() {
            match fs::read_dir(dir) {
                Ok(mut entries) => {
                    if let (None, Some(days)) = (entries.next(), self.unused_days(*mtime)) {
                        self.remove(dir, format_args!("empty, unused {days}d"));
                    }
                }
                Err(e) => self.report(true, format_args!("{}: {e}", dir.display())),
            }
        }
    }

    /// Files and marker-holding dirs become units; other dirs are descended into, and recorded parents first.
    fn collect(&self, dir: &Path, units: &mut Vec<Unit>, dirs: &mut Vec<(PathBuf, SystemTime)>) {
        let entries = match fs::read_dir(dir) {
            Ok(entries) => entries,
            Err(e) => return self.report(true, format_args!("keeping {}: {e}", dir.display())),
        };
        for entry in entries {
            let path = match entry {
                Ok(entry) => entry.path(),
                Err(e) => {
                    self.report(true, format_args!("keeping an entry of {}: {e}", dir.display()));
                    continue;
                }
            };
            let collected = (|| -> io::Result<()> {
                let meta = fs::symlink_metadata(&path)?;
                if meta.is_dir() && !self.is_unit(&path)? {
                    dirs.push((path.clone(), meta.modified()?));
                    self.collect(&path, units, dirs);
                } else {
                    units.push(unit(path.clone())?);
                }
                Ok(())
            })();
            if let Err(e) = collected {
                self.report(true, format_args!("keeping {}: {e}", path.display()));
            }
        }
    }

    fn is_unit(&self, dir: &Path) -> io::Result<bool> {
        for entry in fs::read_dir(dir)? {
            let name = entry?.file_name();
            let name = name.to_string_lossy();
            if self.cfg.unit_markers.iter().any(|m| m.strip_prefix('*').map_or(*m == *name, |suffix| name.ends_with(suffix))) {
                return Ok(true);
            }
        }
        Ok(false)
    }

    fn project_unused_days(&self, project: &Path) -> Option<u64> {
        match unit(project.to_path_buf()) {
            Ok(unit) => self.unused_days(unit.last_use),
            Err(e) => {
                self.report(true, format_args!("keeping artefacts of {}: {e}", project.display()));
                None
            }
        }
    }

    fn clean_old_build_artefacts(&self) {
        println!("\x1b[34mCleaning old build artefacts\x1b[0m");

        for dir in ["tmp", "s", "g", "leetcode", "uni"].map(|d| self.home.join(d)) {
            if !dir.exists() {
                self.report(true, format_args!("Directory {} does not exist", dir.display()));
                continue;
            }

            println!("Searching for stale projects in: \x1b[34m{}\x1b[0m", dir.display());

            let mut walk = WalkDir::new(&dir).into_iter();
            while let Some(entry) = walk.next() {
                let entry = match entry {
                    Ok(entry) => entry,
                    Err(e) => {
                        self.report(true, e);
                        continue;
                    }
                };
                let project = entry.path().parent().unwrap();
                let is_dir = entry.file_type().is_dir();

                match entry.file_name().to_str() {
                    Some("target" | "node_modules") if is_dir => walk.skip_current_dir(),
                    Some("Cargo.toml") if project.join("target").exists() => {
                        if let Some(days) = self.project_unused_days(project) {
                            match self.dry_run {
                                true => self.report(false, format_args!("would cargo clean {} (unused {days}d)", project.display())),
                                false => {
                                    if self.run(Command::new("cargo").arg("clean").current_dir(project)) {
                                        self.report(false, format_args!("cargo clean {} (unused {days}d)", project.display()));
                                    }
                                }
                            }
                        }
                    }
                    // repo root: clean stale dist/ and result/ (nix build symlink)
                    Some(".git") => {
                        if is_dir {
                            walk.skip_current_dir();
                        }
                        let artefacts: Vec<_> = ["dist", "result"].map(|name| project.join(name)).into_iter().filter(|a| a.symlink_metadata().is_ok()).collect();
                        if artefacts.is_empty() {
                            continue;
                        }
                        if let Some(days) = self.project_unused_days(project) {
                            for artefact in &artefacts {
                                self.remove(artefact, format_args!("project unused {days}d"));
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
    }

    fn check_cargo_nix_shadows(&self) {
        let cargo_bin = self.home.join(".cargo/bin");

        let nix_dirs: &[&str] = &[
            "/home/v/.nix-profile/bin",
            "/run/current-system/sw/bin",
            "/home/v/.local/state/nix/profile/bin",
            "/etc/profiles/per-user/v/bin",
        ];

        let entries = match fs::read_dir(&cargo_bin) {
            Ok(e) => e,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return self.report(false, "No cargo/nix binary shadows"),
            Err(e) => return self.report(true, format_args!("{}: {e}", cargo_bin.display())),
        };

        let mut conflicts = vec![];
        for entry in entries {
            let name = match entry {
                Ok(entry) => entry.file_name().to_string_lossy().into_owned(),
                Err(e) => {
                    self.report(true, format_args!("{}: {e}", cargo_bin.display()));
                    continue;
                }
            };
            let nix_match = nix_dirs.iter().any(|nix_dir| {
                let nix_path = PathBuf::from(nix_dir).join(&name);
                if !nix_path.exists() {
                    return false;
                }
                let real = fs::canonicalize(&nix_path).unwrap_or_else(|e| panic!("{}: {e}", nix_path.display()));
                // Rustup shims appear in nix because rustup itself is nix-managed — not a real conflict.
                !real.to_string_lossy().contains("-rustup-")
            });
            if nix_match {
                conflicts.push(name);
            }
        }

        conflicts.sort();
        if conflicts.is_empty() {
            self.report(false, "No cargo/nix binary shadows");
        }
        for name in &conflicts {
            self.report(true, format_args!("cargo shadow: `{name}` exists in ~/.cargo/bin but is also provided by nix — remove the cargo-installed copy"));
        }
    }
}

/// `last_use` is the newest of files' max(atime, mtime) and dirs' mtime: readdir bumps dir atime, our own walks included.
fn unit(path: PathBuf) -> io::Result<Unit> {
    let (mut last_use, mut bytes) = (UNIX_EPOCH, 0);
    for entry in WalkDir::new(&path) {
        let meta = entry?.metadata()?;
        let used = match meta.is_dir() {
            true => meta.modified()?,
            false => meta.modified()?.max(meta.accessed()?),
        };
        last_use = last_use.max(used);
        bytes += meta.blocks() * 512;
    }
    Ok(Unit { path, last_use, bytes })
}
