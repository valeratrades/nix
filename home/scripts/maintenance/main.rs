#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
v_utils = "2"
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
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use v_utils::Percent;
use walkdir::WalkDir;

/// System maintenance script
#[derive(Parser, Debug)]
#[command(name = "maintenance")]
#[command(about = "System maintenance: clean outdated ~/tmp, ~/.cache and build artefacts, refresh nightly version cache, and rebuild NixOS")]
struct Args {
    #[command(subcommand)]
    cmd: Option<Cmd>,

    /// Skip the NixOS rebuild step
    #[arg(long)]
    skip_rebuild: bool,

    /// Only run specific tasks (comma-separated: clean,cache,nightly,shadows,redirects,rebuild)
    #[arg(long)]
    only: Option<String>,

    /// Report what would be removed, then stop before touching anything
    #[arg(long)]
    dry_run: bool,
}

#[derive(clap::Subcommand, Debug)]
enum Cmd {
    /// Move `from` to `to`, leaving `from` as a redirect the `redirects` task removes once unfollowed for stale_multipliers.redirects
    Mv { from: PathBuf, to: PathBuf },
}

/// written by home-manager from ./config.nix
#[derive(Deserialize)]
struct Config {
    stale_after_days: u64,
    stale_multipliers: StaleMultipliers,
    unit_markers: Vec<String>,
    cache_limit_gb: u64,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct StaleMultipliers {
    llm_worktrees: Percent,
    redirects: Percent,
}

impl Config {
    fn stale_days(&self, multiplier: Percent) -> u64 {
        (self.stale_after_days as f64 * *multiplier).round() as u64
    }
}

struct Ctx {
    cfg: Config,
    home: PathBuf,
    redirects: PathBuf,
    log: PathBuf,
    last_clean: PathBuf,
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
        redirects: state.join("maintenance/redirects"),
        log: state.join("maintenance/log"),
        last_clean: state.join("maintenance/last_clean"),
        dry_run: args.dry_run,
    };
    if let Some(Cmd::Mv { from, to }) = args.cmd {
        return ctx.mv(&from, &to);
    }

    let tasks: Vec<&str> = match args.only {
        Some(ref only) => only.split(',').collect(),
        None => vec!["clean", "cache", "nightly", "shadows", "redirects", "rebuild"],
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
        if tasks.contains(&"redirects") {
            s.spawn(|| ctx.sweep_redirects());
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

    fn unused_days(&self, last_use: SystemTime, stale_after_days: u64) -> Option<u64> {
        let days = last_use.elapsed().map_or(0, |e| e.as_secs() / 86400); // Err: last use is in the future, so in use
        (days >= stale_after_days).then_some(days)
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
        println!("\x1b[34mSweeping {} for units unused for {} days\x1b[0m", root.display(), self.cfg.stale_after_days);
        let (mut units, mut dirs) = (vec![], vec![]);
        self.collect(root, &mut units, &mut dirs);
        units.sort_by_key(|u| u.last_use);
        let mut kept: u64 = units.iter().map(|u| u.bytes).sum();
        for unit in &units {
            let days = self.unused_days(unit.last_use, self.cfg.stale_after_days);
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
                    if let (None, Some(days)) = (entries.next(), self.unused_days(*mtime, self.cfg.stale_after_days)) {
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

    fn project_last_use(&self, project: &Path) -> Option<SystemTime> {
        match unit(project.to_path_buf()) {
            Ok(unit) => Some(unit.last_use),
            Err(e) => {
                self.report(true, format_args!("keeping artefacts of {}: {e}", project.display()));
                None
            }
        }
    }

    fn clean_old_build_artefacts(&self) {
        println!("\x1b[34mCleaning old build artefacts\x1b[0m");
        let started = SystemTime::now();
        let last_clean = match fs::read_to_string(&self.last_clean) {
            Ok(secs) => UNIX_EPOCH + Duration::from_secs(secs.trim().parse().unwrap_or_else(|e| panic!("{}: {e}", self.last_clean.display()))),
            Err(e) if e.kind() == io::ErrorKind::NotFound => UNIX_EPOCH, // never cleaned: everything was touched since
            Err(e) => panic!("{}: {e}", self.last_clean.display()),
        };
        let cargo = |project: &Path, args: &[&str], why: String| match self.dry_run {
            true => self.report(false, format_args!("would cargo {} {} ({why})", args.join(" "), project.display())),
            false => {
                if self.run(Command::new("cargo").args(args).current_dir(project)) {
                    self.report(false, format_args!("cargo {} {} ({why})", args.join(" "), project.display()));
                }
            }
        };
        let sweep_days = self.cfg.stale_after_days.to_string();

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
                        let Some(last_use) = self.project_last_use(project) else { continue };
                        match self.unused_days(last_use, self.cfg.stale_after_days) {
                            Some(days) => cargo(project, &["clean"], format!("unused {days}d")),
                            None if last_use > last_clean => cargo(project, &["sweep", "--time", &sweep_days], "touched since last clean".into()),
                            None => {}
                        }
                    }
                    Some("worktrees") if is_dir && project.ends_with(".claude") => self.remove_stale_worktrees(entry.path()), // before the walk reads it, so it descends only into survivors
                    // repo root: clean stale dist/ and result/ (nix build symlink)
                    Some(".git") => {
                        if is_dir {
                            walk.skip_current_dir();
                        }
                        let artefacts: Vec<_> = ["dist", "result"].map(|name| project.join(name)).into_iter().filter(|a| a.symlink_metadata().is_ok()).collect();
                        if artefacts.is_empty() {
                            continue;
                        }
                        if let Some(days) = self.project_last_use(project).and_then(|t| self.unused_days(t, self.cfg.stale_after_days)) {
                            for artefact in &artefacts {
                                self.remove(artefact, format_args!("project unused {days}d"));
                            }
                        }
                    }
                    _ => {}
                }
            }
        }

        if !self.dry_run {
            let secs = started.duration_since(UNIX_EPOCH).unwrap().as_secs();
            fs::write(&self.last_clean, secs.to_string()).unwrap_or_else(|e| panic!("{}: {e}", self.last_clean.display()));
        }
    }

    /// plain `git worktree remove` refuses dirty or locked worktrees, so only uncommitted-nothing goes; the branch stays
    fn remove_stale_worktrees(&self, worktrees: &Path) {
        let stale_after_days = self.cfg.stale_days(self.cfg.stale_multipliers.llm_worktrees);
        let repo = worktrees.parent().and_then(Path::parent).expect("<repo>/.claude/worktrees");
        let entries = match fs::read_dir(worktrees) {
            Ok(entries) => entries,
            Err(e) => return self.report(true, format_args!("keeping {}: {e}", worktrees.display())),
        };
        for entry in entries {
            let worktree = match entry {
                Ok(entry) => entry.path(),
                Err(e) => {
                    self.report(true, format_args!("keeping an entry of {}: {e}", worktrees.display()));
                    continue;
                }
            };
            let Some(days) = self.project_last_use(&worktree).and_then(|t| self.unused_days(t, stale_after_days)) else { continue };
            if self.dry_run {
                self.report(false, format_args!("would git worktree remove {} (unused {days}d)", worktree.display()));
            } else if self.run(Command::new("git").arg("-C").arg(repo).args(["worktree", "remove"]).arg(&worktree)) {
                self.report(false, format_args!("git worktree remove {} (unused {days}d)", worktree.display()));
            }
        }
    }

    /// `~/<p>` -> `$XDG_STATE_HOME/maintenance/redirects/<p>` -> new location: only traversals reach the hop, so its atime is the last follow (`ls -l` readlinks just the front)
    fn mv(&self, from: &Path, to: &Path) {
        let from = fs::canonicalize(from).unwrap_or_else(|e| panic!("{}: {e}", from.display()));
        let to = std::path::absolute(to).unwrap_or_else(|e| panic!("{}: {e}", to.display()));
        let to = fs::canonicalize(to.parent().expect("absolute, and not /")).unwrap_or_else(|e| panic!("{}: {e}", to.display())).join(to.file_name().expect("absolute, and not /"));
        let hop = self.redirects.join(from.strip_prefix(&self.home).unwrap_or_else(|_| panic!("{} is outside $HOME", from.display())));
        for taken in [&to, &hop] {
            assert!(fs::symlink_metadata(taken).is_err_and(|e| e.kind() == io::ErrorKind::NotFound), "{} already exists", taken.display());
        }
        fs::create_dir_all(hop.parent().expect("under redirects")).unwrap_or_else(|e| panic!("{}: {e}", hop.display()));
        fs::rename(&from, &to).unwrap_or_else(|e| panic!("{} -> {}: {e}", from.display(), to.display()));
        std::os::unix::fs::symlink(&to, &hop).unwrap_or_else(|e| panic!("{}: {e}", hop.display()));
        std::os::unix::fs::symlink(&hop, &from).unwrap_or_else(|e| panic!("{}: {e}", from.display()));
        self.report(false, format_args!("moved {} -> {}, redirect lives until unfollowed {}d", from.display(), to.display(), self.cfg.stale_days(self.cfg.stale_multipliers.redirects)));
    }

    fn sweep_redirects(&self) {
        let hops = &self.redirects;
        println!("\x1b[34mSweeping redirects in {} unfollowed for {} days\x1b[0m", hops.display(), self.cfg.stale_days(self.cfg.stale_multipliers.redirects));
        for entry in WalkDir::new(hops).min_depth(1) {
            let entry = match entry {
                Ok(entry) => entry,
                Err(e) if e.io_error().is_some_and(|e| e.kind() == io::ErrorKind::NotFound) && e.depth() == 0 => return,
                Err(e) => {
                    self.report(true, e);
                    continue;
                }
            };
            if entry.file_type().is_dir() {
                continue;
            }
            let hop = entry.path();
            let front = self.home.join(hop.strip_prefix(hops).expect("walked from hops"));
            let unused_days = (|| -> io::Result<u64> {
                if !entry.file_type().is_symlink() {
                    return Err(io::Error::other("hop is not a symlink"));
                }
                let target = fs::read_link(&front)?;
                if target != hop {
                    return Err(io::Error::other(format!("{} points to {}, not the hop", front.display(), target.display())));
                }
                Ok(fs::symlink_metadata(hop)?.accessed()?.elapsed().map_or(0, |e| e.as_secs() / 86400)) // Err: followed in the future, so in use
            })();
            match unused_days {
                Ok(days) if days >= self.cfg.stale_days(self.cfg.stale_multipliers.redirects) => {
                    self.remove(&front, format_args!("redirect unfollowed {days}d"));
                    self.remove(hop, format_args!("hop of {}", front.display()));
                }
                Ok(_) => {}
                Err(e) => self.report(true, format_args!("keeping redirect {}: {e}", hop.display())),
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
