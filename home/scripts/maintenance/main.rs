#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = { version = "1", features = ["preserve_order"] }
sha2 = "0.10"
v_utils = "2"
walkdir = "2"
---

use clap::Parser;
use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::fmt::Display;
use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
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
    /// Move `from` to `to`, leaving `from` as a redirect the `redirects` task removes once unfollowed for stale_multipliers.redirects.
    /// Then re-roots what records the old path: git worktree links, tmux sessions, claude projects/history/config, direnv trust, zoxide. A `from` already redirecting to `to` gets just that.
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
    state: PathBuf,
    data: PathBuf,
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
        state: state.clone(),
        data: PathBuf::from(env("XDG_DATA_HOME")),
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

    fn hop(&self, front: &Path) -> PathBuf {
        self.redirects.join(front.strip_prefix(&self.home).unwrap_or_else(|_| panic!("{} is outside $HOME", front.display())))
    }

    fn mv(&self, from: &Path, to: &Path) {
        let [from, to] = [from, to].map(|p| {
            let p = std::path::absolute(p).unwrap_or_else(|e| panic!("{}: {e}", p.display()));
            let parent = fs::canonicalize(p.parent().expect("absolute, and not /")).unwrap_or_else(|e| panic!("{}: {e}", p.display()));
            parent.join(p.file_name().expect("absolute, and not /"))
        });
        let moved = fs::read_link(&from).is_ok_and(|hop| hop == self.hop(&from) && fs::read_link(&hop).is_ok_and(|target| target == to));
        if !moved {
            let meta = fs::symlink_metadata(&from).unwrap_or_else(|e| panic!("{}: {e}", from.display()));
            assert!(!meta.is_symlink(), "{} is a symlink not redirecting to {}", from.display(), to.display());
            self.relocate(&from, &to);
        }
        let [from, to] = [&from, &to].map(|p| p.to_str().unwrap_or_else(|| panic!("{} is not UTF-8", p.display())));
        self.rebase_git(from, to);
        self.rebase_tmux(from, to);
        self.rebase_claude(from, to);
        self.rebase_direnv(from, to);
        self.rebase_zoxide(from, to);
    }

    fn relocate(&self, from: &Path, to: &Path) {
        for taken in [to, &self.hop(from)] {
            assert!(fs::symlink_metadata(taken).is_err_and(|e| e.kind() == io::ErrorKind::NotFound), "{} already exists", taken.display());
        }
        fs::rename(from, to).unwrap_or_else(|e| panic!("{} -> {}: {e}", from.display(), to.display()));
        self.redirect(from, to);
        self.report(false, format_args!("moved {} -> {}, redirect lives until unfollowed {}d", from.display(), to.display(), self.cfg.stale_days(self.cfg.stale_multipliers.redirects)));
    }

    /// `~/<p>` -> `$XDG_STATE_HOME/maintenance/redirects/<p>` -> new location: only traversals reach the hop, so its atime is the last follow (`ls -l` readlinks just the front)
    fn redirect(&self, from: &Path, to: &Path) {
        let hop = self.hop(from);
        assert!(fs::symlink_metadata(&hop).is_err_and(|e| e.kind() == io::ErrorKind::NotFound), "{} already exists", hop.display());
        fs::create_dir_all(hop.parent().expect("under redirects")).unwrap_or_else(|e| panic!("{}: {e}", hop.display()));
        std::os::unix::fs::symlink(to, &hop).unwrap_or_else(|e| panic!("{}: {e}", hop.display()));
        std::os::unix::fs::symlink(&hop, from).unwrap_or_else(|e| panic!("{}: {e}", from.display()));
    }

    /// Replaces `path` with `edit`'s output if that differs, keeping its mode. False if `path` is missing.
    fn rewrite(&self, path: &Path, edit: impl FnOnce(&str) -> String) -> bool {
        let (old, meta) = match fs::read_to_string(path).and_then(|old| Ok((old, fs::metadata(path)?))) {
            Ok(read) => read,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return false,
            Err(e) => {
                self.report(true, format_args!("{}: {e}", path.display()));
                return true;
            }
        };
        let new = edit(&old);
        if new == old {
            return true;
        }
        let tmp = PathBuf::from(format!("{}.maintenance-tmp", path.display()));
        let written = fs::write(&tmp, &new).and_then(|()| fs::set_permissions(&tmp, meta.permissions())).and_then(|()| fs::rename(&tmp, path)); // rename: claude reads its files concurrently
        match written {
            Ok(()) => self.report(false, format_args!("rebased paths in {}", path.display())),
            Err(e) => self.report(true, format_args!("{}: {e}", path.display())),
        }
        true
    }

    /// Re-roots the path a worktree link holds (`gitdir: <p>` in a `.git` file, bare in `.git/worktrees/<n>/gitdir`), returning where it points.
    fn rebase_link(&self, link: &Path, from: &str, to: &str) -> Option<PathBuf> {
        let mut target = None;
        let exists = self.rewrite(link, |old| {
            let old = old.trim_end();
            let (prefix, path) = old.strip_prefix("gitdir: ").map_or(("", old), |path| ("gitdir: ", path));
            let path = rebase(path, from, to).unwrap_or_else(|| path.to_owned());
            target = Some(link.parent().expect("a file in a dir").join(&path)); // submodules' links are relative
            format!("{prefix}{path}\n")
        });
        if !exists {
            self.report(true, format_args!("dangling worktree link: {} is missing", link.display()));
        }
        target
    }

    /// Worktree links are absolute both ways, and git keeps accepting the old side while the redirect resolves.
    fn rebase_git(&self, from: &str, to: &str) {
        let mut walk = WalkDir::new(to).into_iter();
        while let Some(entry) = walk.next() {
            let entry = match entry {
                Ok(entry) => entry,
                Err(e) => {
                    self.report(true, e);
                    continue;
                }
            };
            let is_dir = entry.file_type().is_dir();
            match entry.file_name().to_str() {
                Some("target" | "node_modules" | ".direnv") if is_dir => walk.skip_current_dir(),
                Some(".git") if is_dir => {
                    walk.skip_current_dir();
                    let admins = match fs::read_dir(entry.path().join("worktrees")) {
                        Ok(admins) => admins,
                        Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
                        Err(e) => {
                            self.report(true, format_args!("{}: {e}", entry.path().display()));
                            continue;
                        }
                    };
                    for admin in admins {
                        match admin {
                            Ok(admin) => {
                                if let Some(worktree) = self.rebase_link(&admin.path().join("gitdir"), from, to) {
                                    self.rebase_link(&worktree, from, to);
                                }
                            }
                            Err(e) => self.report(true, format_args!("{}: {e}", entry.path().display())),
                        }
                    }
                }
                Some(".git") => {
                    if let Some(admin) = self.rebase_link(entry.path(), from, to)
                        && admin.parent().is_some_and(|p| p.ends_with("worktrees"))
                    {
                        self.rebase_link(&admin.join("gitdir"), from, to);
                    }
                }
                _ => {}
            }
        }
    }

    fn rebase_tmux(&self, from: &str, to: &str) {
        let sessions = Command::new("tmux").args(["list-sessions", "-F", "#{session_name}\t#{session_path}"]).output().expect("tmux is installed");
        let stderr = String::from_utf8_lossy(&sessions.stderr);
        if !sessions.status.success() && !stderr.contains("no server running") && !stderr.contains("error connecting") {
            self.report(true, format_args!("tmux list-sessions: {stderr}"));
        }
        for line in String::from_utf8(sessions.stdout).expect("tmux session paths are UTF-8").lines() {
            let (name, path) = line.split_once('\t').expect("format string has a tab");
            let Some(path) = rebase(path, from, to) else { continue };
            // a control-mode client attaches without a terminal, and attach's `-c` is the only setter of session_path
            if self.run(Command::new("tmux").args(["-C", "attach-session", "-t", &format!("={name}"), "-c", &path]).stdin(Stdio::null()).stdout(Stdio::null())) {
                self.report(false, format_args!("tmux session {name} now starts in {path}"));
            }
        }
        for tsv in ["tmux_sessions.tsv", "claude_restore.tsv"] {
            self.rewrite(&self.state.join(tsv), |old| {
                old.lines()
                    .map(|line| {
                        let mut fields: Vec<String> = line.split('\t').map(str::to_owned).collect();
                        if let Some(path) = rebase(&fields[1], from, to) {
                            fields[1] = path; // both files keep the path second
                        }
                        fields.join("\t") + "\n"
                    })
                    .collect()
            });
        }
    }

    /// `~/.claude`, and `~/.claude-accountN` of `--acc N`
    fn claude_dirs(&self) -> Vec<PathBuf> {
        let entries = fs::read_dir(&self.home).unwrap_or_else(|e| panic!("{}: {e}", self.home.display()));
        let dirs = entries.map(|entry| entry.unwrap_or_else(|e| panic!("{}: {e}", self.home.display())).path());
        dirs.filter(|dir| dir.file_name().is_some_and(|n| n == ".claude" || n.to_string_lossy().starts_with(".claude-account"))).collect()
    }

    /// `(cwd, pid)` per running claude; the cwd is the one it started in, which a move leaves behind
    fn live_claudes(&self) -> Vec<(String, u64)> {
        let mut live = vec![];
        for sessions in self.claude_dirs().into_iter().map(|dir| dir.join("sessions")) {
            let entries = match fs::read_dir(&sessions) {
                Ok(entries) => entries,
                Err(e) if e.kind() == io::ErrorKind::NotFound => continue, // account never ran an interactive session
                Err(e) => panic!("{}: {e}", sessions.display()),
            };
            for f in entries.map(|f| f.unwrap_or_else(|e| panic!("{}: {e}", sessions.display())).path()) {
                if f.extension().is_none_or(|e| e != "json") {
                    continue;
                }
                let session: Value = match fs::read_to_string(&f) {
                    Ok(raw) => serde_json::from_str(&raw).unwrap_or_else(|e| panic!("{}: {e}", f.display())),
                    Err(e) if e.kind() == io::ErrorKind::NotFound => continue, // its claude exited since listing
                    Err(e) => panic!("{}: {e}", f.display()),
                };
                let pid = session["pid"].as_u64().unwrap_or_else(|| panic!("{}: no pid", f.display()));
                let cwd = session["cwd"].as_str().unwrap_or_else(|| panic!("{}: no cwd", f.display()));
                if Path::new(&format!("/proc/{pid}")).exists() {
                    live.push((cwd.to_owned(), pid));
                }
            }
        }
        live
    }

    /// history and config hold the path itself
    fn rebase_claude(&self, from: &str, to: &str) {
        let (old, new) = (claude_encode(from), claude_encode(to));
        if let Some(alike) = alike_encoded(Path::new("/"), &old) {
            return self.report(true, format_args!("left claude projects of {from} in place: {} encodes alike", alike.display()));
        }
        for dir in self.claude_dirs() {
            let name = dir.file_name().expect("listed").to_string_lossy().into_owned();
            let projects = dir.join("projects");
            match fs::read_dir(&projects) {
                Ok(entries) => {
                    for entry in entries {
                        let project = entry.unwrap_or_else(|e| panic!("{}: {e}", projects.display())).path();
                        let name = project.file_name().expect("listed").to_str().expect("claude encodes to ASCII");
                        let Some(rest) = name.strip_prefix(&old).filter(|rest| rest.is_empty() || rest.starts_with('-')) else { continue };
                        if project.is_symlink() {
                            continue; // an earlier move's redirect
                        }
                        let target = projects.join(format!("{new}{rest}"));
                        assert!(target.file_name().expect("joined").len() <= 200, "{}: claude hashes names past 200 chars", target.display());
                        match fs::symlink_metadata(&target) {
                            Err(e) if e.kind() == io::ErrorKind::NotFound => self.relocate(&project, &target),
                            Ok(_) if self.merge(&project, &target) => {
                                fs::remove_dir(&project).unwrap_or_else(|e| panic!("{}: {e}", project.display()));
                                self.redirect(&project, &target);
                                self.report(false, format_args!("merged {} into {}", project.display(), target.display()));
                            }
                            Ok(_) => {}
                            Err(e) => panic!("{}: {e}", target.display()),
                        }
                    }
                }
                Err(e) if e.kind() == io::ErrorKind::NotFound => {}
                Err(e) => self.report(true, format_args!("{}: {e}", projects.display())),
            }
            self.rewrite(&dir.join("history.jsonl"), |old| {
                old.lines()
                    .enumerate()
                    .map(|(i, line)| {
                        let mut entry: Value = match serde_json::from_str(line) {
                            Ok(entry) => entry,
                            Err(e) => {
                                self.report(true, format_args!("{}:{}: {e}, left as is", dir.join("history.jsonl").display(), i + 1));
                                return format!("{line}\n");
                            }
                        };
                        match entry["project"].as_str().and_then(|project| rebase(project, from, to)) {
                            Some(project) => {
                                entry["project"] = Value::String(project);
                                entry.to_string() + "\n"
                            }
                            None => format!("{line}\n"),
                        }
                    })
                    .collect()
            });
            let config = match name.as_str() {
                ".claude" => self.home.join(".claude.json"),
                _ => dir.join(".claude.json"),
            };
            self.rewrite(&config, |old| {
                let mut config: Value = serde_json::from_str(old).unwrap_or_else(|e| panic!("{}: {e}", config.display()));
                match self.rebase_json(&mut config, from, to) {
                    true => serde_json::to_string_pretty(&config).expect("was json"),
                    false => old.to_owned(),
                }
            });
        }
    }

    /// Re-roots every string and key under `from`; a key already present at its new path wins over the old one.
    fn rebase_json(&self, value: &mut Value, from: &str, to: &str) -> bool {
        match value {
            Value::String(s) => match rebase(s, from, to) {
                Some(new) => {
                    *s = new;
                    true
                }
                None => false,
            },
            Value::Array(values) => values.iter_mut().fold(false, |changed, v| self.rebase_json(v, from, to) | changed),
            Value::Object(map) => {
                let changed = map.values_mut().fold(false, |changed, v| self.rebase_json(v, from, to) | changed);
                let keys: Vec<(String, String)> = map.keys().filter_map(|key| Some((key.clone(), rebase(key, from, to)?))).collect();
                for (key, new) in &keys {
                    let value = map.shift_remove(key).expect("listed above");
                    match map.contains_key(new) {
                        true => self.report(true, format_args!("dropped claude config of {key}: {new} has its own")),
                        false => _ = map.insert(new.clone(), value),
                    }
                }
                changed || !keys.is_empty()
            }
            _ => false,
        }
    }

    /// Moves `src`'s entries into `dst`, recursing into dirs both have. False if a name taken in both kept `src` non-empty.
    fn merge(&self, src: &Path, dst: &Path) -> bool {
        let mut emptied = true;
        for entry in fs::read_dir(src).unwrap_or_else(|e| panic!("{}: {e}", src.display())) {
            let entry = entry.unwrap_or_else(|e| panic!("{}: {e}", src.display()));
            let (from, to) = (entry.path(), dst.join(entry.file_name()));
            match fs::symlink_metadata(&to) {
                Err(e) if e.kind() == io::ErrorKind::NotFound => fs::rename(&from, &to).unwrap_or_else(|e| panic!("{} -> {}: {e}", from.display(), to.display())),
                Ok(meta) if meta.is_dir() && entry.file_type().is_ok_and(|t| t.is_dir()) => match self.merge(&from, &to) {
                    true => fs::remove_dir(&from).unwrap_or_else(|e| panic!("{}: {e}", from.display())),
                    false => emptied = false,
                },
                Ok(_) => {
                    self.report(true, format_args!("kept {}: {} is taken", from.display(), to.display()));
                    emptied = false;
                }
                Err(e) => panic!("{}: {e}", to.display()),
            }
        }
        emptied
    }

    /// direnv trusts `allow/sha256(<rc path>\n<rc>)`; only a trust still current at the old path carries over.
    fn rebase_direnv(&self, from: &str, to: &str) {
        let allow = self.data.join("direnv/allow");
        let entries = match fs::read_dir(&allow) {
            Ok(entries) => entries,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return,
            Err(e) => return self.report(true, format_args!("{}: {e}", allow.display())),
        };
        let hash = |path: &str, rc: &[u8]| format!("{:x}", Sha256::new().chain_update(path).chain_update("\n").chain_update(rc).finalize());
        for entry in entries {
            let entry = entry.unwrap_or_else(|e| panic!("{}: {e}", allow.display())).path();
            let old = fs::read_to_string(&entry).unwrap_or_else(|e| panic!("{}: {e}", entry.display()));
            let old = old.trim_end();
            let Some(new) = rebase(old, from, to) else { continue };
            let rc = match fs::read(&new) {
                Ok(rc) => rc,
                Err(e) if e.kind() == io::ErrorKind::NotFound => continue, // rc deleted since, nothing to trust
                Err(e) => {
                    self.report(true, format_args!("{new}: {e}"));
                    continue;
                }
            };
            if entry.file_name().is_none_or(|name| *name != *hash(old, &rc)) {
                continue; // trusted an older revision of the rc
            }
            let trust = allow.join(hash(&new, &rc));
            if !trust.exists() {
                fs::write(&trust, format!("{new}\n")).unwrap_or_else(|e| panic!("{}: {e}", trust.display()));
                self.report(false, format_args!("direnv trusts {new}"));
            }
        }
    }

    fn rebase_zoxide(&self, from: &str, to: &str) {
        let listed = Command::new("zoxide").args(["query", "--list", "--score"]).current_dir("/").output().expect("zoxide is installed"); // `/`: query leaves out the cwd
        if !listed.status.success() {
            return self.report(true, format_args!("zoxide query: {}", String::from_utf8_lossy(&listed.stderr)));
        }
        let listed = String::from_utf8(listed.stdout).expect("zoxide paths are UTF-8");
        let moved: Vec<(&str, &str, String)> = listed
            .lines()
            .filter_map(|line| {
                let (score, path) = line.trim_start().split_once(' ').expect("`<score> <path>`");
                Some((score, path, rebase(path, from, to)?))
            })
            .collect();
        // removes first: each add may age out low-ranked entries, listed ones included
        let removed: Vec<_> = moved.into_iter().filter(|(_, path, _)| self.run(Command::new("zoxide").args(["remove", path]))).collect();
        for (score, path, new) in removed {
            if self.run(Command::new("zoxide").args(["add", "--score", score, &new])) {
                self.report(false, format_args!("zoxide: {path} -> {new}"));
            }
        }
    }

    /// Claude scans every `projects/` dir, so for those the follow that counts is a live claude still writing there, not atime.
    fn sweep_redirects(&self) {
        let hops = &self.redirects;
        let live = self.live_claudes();
        let claude_projects: Vec<PathBuf> = self.claude_dirs().into_iter().map(|dir| dir.join("projects")).collect();
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
            let front_str = front.to_str().expect("fronts are UTF-8 paths");
            let holders = |claude_dir: bool| -> Vec<String> {
                let held = |cwd: &str| match claude_dir {
                    true => front.file_name().is_some_and(|name| *name == *claude_encode(cwd)),
                    false => rebase(cwd, front_str, front_str).is_some(),
                };
                live.iter().filter(|(cwd, _)| held(cwd)).map(|(cwd, pid)| format!("claude {pid} in {cwd}")).collect()
            };
            if front.parent().is_some_and(|p| claude_projects.iter().any(|projects| projects == p)) {
                match holders(true).as_slice() {
                    [] => {
                        self.remove(&front, "redirect no live claude writes through");
                        self.remove(hop, format_args!("hop of {}", front.display()));
                    }
                    holders => self.report(true, format_args!("{} still written by {}", front.display(), holders.join(", "))),
                }
                continue;
            }
            let last_follow = (|| -> io::Result<(u64, bool)> {
                if !entry.file_type().is_symlink() {
                    return Err(io::Error::other("hop is not a symlink"));
                }
                let target = fs::read_link(&front)?;
                if target != hop {
                    return Err(io::Error::other(format!("{} points to {}, not the hop", front.display(), target.display())));
                }
                let meta = fs::symlink_metadata(hop)?;
                let days = meta.accessed()?.elapsed().map_or(0, |e| e.as_secs() / 86400); // Err: followed in the future, so in use
                Ok((days, meta.accessed()? > meta.modified()?)) // a symlink's mtime is its creation, the move
            })();
            match last_follow {
                Ok((days, _)) if days >= self.cfg.stale_days(self.cfg.stale_multipliers.redirects) => {
                    self.remove(&front, format_args!("redirect unfollowed {days}d"));
                    self.remove(hop, format_args!("hop of {}", front.display()));
                }
                Ok((days, true)) => match holders(false).as_slice() {
                    [] => self.report(true, format_args!("{} was followed {days}d ago: something still points at the old path", front.display())),
                    holders => self.report(true, format_args!("{} was followed {days}d ago, and {} still started under it", front.display(), holders.join(", "))),
                },
                Ok((_, false)) => {}
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

/// the `projects/` dir name claude gives a cwd
fn claude_encode(path: &str) -> String {
    path.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect()
}

/// `path` re-rooted from `from` onto `to`, if it lies under `from`
fn rebase(path: &str, from: &str, to: &str) -> Option<String> {
    let rest = path.strip_prefix(from)?;
    (rest.is_empty() || rest.starts_with('/')).then(|| format!("{to}{rest}"))
}

/// A real path under `dir` whose encoding is `encoded`, or starts with it at a `-` boundary; `from` itself is a redirect by now, which this skips.
fn alike_encoded(dir: &Path, encoded: &str) -> Option<PathBuf> {
    let encoded = encoded.strip_prefix('-').expect("encodes an absolute path");
    for entry in fs::read_dir(dir).ok()? { // unreadable: nothing claude ran in
        let Ok(entry) = entry else { continue };
        if !entry.file_type().is_ok_and(|t| t.is_dir()) {
            continue;
        }
        let name = claude_encode(&entry.file_name().to_string_lossy());
        if name == encoded || name.starts_with(&format!("{encoded}-")) {
            return Some(entry.path());
        }
        if let Some(rest) = encoded.strip_prefix(&name).filter(|rest| rest.starts_with('-'))
            && let Some(alike) = alike_encoded(&entry.path(), rest)
        {
            return Some(alike);
        }
    }
    None
}
