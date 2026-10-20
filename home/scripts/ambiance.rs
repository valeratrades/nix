#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
tokio = { version = "1", features = ["full"] }
libc = "0.2"
crossterm = "0.28"
---
// a thing to procedurally set up environment for performing distinctly different and cognitively demanding tasks

use clap::{Parser, Subcommand};
use std::process::Stdio;
use tokio::process::Command;
use tokio::signal;

#[path = "timer.rs"]
pub mod timer; // pub so its `main` isn't dead code here
#[path = "shared/keys.rs"]
mod keys;

#[derive(Parser, Debug)]
#[command(name = "ambiance")]
#[command(about = "Set up work ambiance")]
struct Args {
    #[command(subcommand)]
    command: Commands,

    /// Run a `timer` alongside; takes the same input. Without a value, counts up.
    #[arg(short, long, global = true, num_args = 0..=1)]
    timer: Option<Option<timer::Countdown>>,

    /// Run alongside the previous `timer`'s countdown; same as `timer --continue`
    #[arg(short = 'c', long = "continue", global = true, conflicts_with = "timer")]
    cont: bool,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Set up ambiance for learning math (browser-based, legacy)
    MathFirefox,
    /// Set up ambiance for learning math (local)
    Math,
}

fn home() -> String {
    std::env::var("HOME").expect("HOME not set")
}

struct WallpaperGuard {
    image: String,
    mode: String,
}

impl WallpaperGuard {
    fn capture() -> Self {
        let entries = std::fs::read_dir("/proc").expect("failed to read /proc");
        for entry in entries.flatten() {
            let pid_str = entry.file_name();
            let pid_str = pid_str.to_string_lossy();
            if !pid_str.chars().all(|c| c.is_ascii_digit()) {
                continue;
            }
            let Ok(cmdline) = std::fs::read(format!("/proc/{pid_str}/cmdline")) else {
                continue;
            };
            let args: Vec<String> = cmdline
                .split(|&b| b == 0)
                .filter(|s| !s.is_empty())
                .map(|s| String::from_utf8_lossy(s).into_owned())
                .collect();
            if !args.first().map(|s| s.contains("swaybg")).unwrap_or(false) {
                continue;
            }
            let mut image = None;
            let mut mode = None;
            let mut iter = args[1..].iter();
            while let Some(arg) = iter.next() {
                match arg.as_str() {
                    "-i" => image = iter.next().cloned(),
                    "-m" => mode = iter.next().cloned(),
                    _ => {}
                }
            }
            return Self {
                image: image.expect("swaybg has no -i arg"),
                mode: mode.expect("swaybg has no -m arg"),
            };
        }
        panic!("no swaybg process found");
    }
}

impl Drop for WallpaperGuard {
    fn drop(&mut self) {
        let _ = std::process::Command::new("swaymsg")
            .args(["output", "eDP-1", "bg", &self.image, &self.mode])
            .status();
    }
}

struct Ambiance {
    wallpaper: WallpaperGuard,
    children: Vec<tokio::process::Child>,
}

impl Ambiance {
    fn new(wallpaper: WallpaperGuard) -> Self {
        Self {
            wallpaper,
            children: Vec::new(),
        }
    }

    fn own(&mut self, child: tokio::process::Child) {
        self.children.push(child);
    }
}

impl Drop for Ambiance {
    fn drop(&mut self) {
        for child in &mut self.children {
            if let Some(pid) = child.id() {
                unsafe { libc::kill(-(pid as i32), libc::SIGTERM) };
                let _ = child.start_kill();
            }
        }
        let _ = std::process::Command::new("tedi")
            .args(["sprints", "selected", "halt"])
            .status();
        println!("Restoring wallpaper: {}", self.wallpaper.image);
    }
}

fn kill_running_pp() {
    // Kill mpv instances spawned by the `pp` fish function.
    // These have a distinctive flag combination: --no-terminal --no-video --loop-file --loop-playlist
    let output = std::process::Command::new("pgrep")
        .args([
            "-f",
            "mpv --no-terminal --no-video --loop-file --loop-playlist",
        ])
        .output()
        .expect("failed to run pgrep");
    if output.status.success() {
        let pids = String::from_utf8_lossy(&output.stdout);
        for pid in pids.lines() {
            let pid = pid.trim();
            if !pid.is_empty() {
                println!("Killing pp instance (mpv pid {pid})");
                let _ = std::process::Command::new("kill").arg(pid).status();
            }
        }
    }
}

fn is_running(process_name: &str) -> bool {
    std::process::Command::new("pgrep")
        .args(["-x", process_name])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn parse_sink_input_id(line: &str, name: &str) -> Option<String> {
    if !line.starts_with("Sink input:") {
        return None;
    }
    if !line.contains(&format!("Name: {name},")) {
        return None;
    }
    let id_start = line.find("ID: ")? + 4;
    let id_end = line[id_start..].find(',')? + id_start;
    Some(line[id_start..id_end].to_string())
}

/// The two streams that make up the ambiance soundscape.
struct Sinks {
    mpv: String,
    bbeats: String,
}

impl Sinks {
    /// muting stands in for pausing: bbeats runs as root, out of reach of SIGSTOP
    fn set_paused(&self, paused: bool) {
        for id in [&self.mpv, &self.bbeats] {
            let status = std::process::Command::new("pulsemixer")
                .args(["--id", id, if paused { "--mute" } else { "--unmute" }])
                .status()
                .expect("failed to run pulsemixer");
            assert!(status.success(), "pulsemixer mute toggle failed for sink input {id}");
        }
    }
}

async fn balance_volumes() -> Sinks {
    const RATIO: f64 = 0.87;
    const MAX_WAIT: std::time::Duration = std::time::Duration::from_secs(10);
    const POLL_INTERVAL: std::time::Duration = std::time::Duration::from_millis(300);

    let start = std::time::Instant::now();
    loop {
        let output = std::process::Command::new("pulsemixer")
            .arg("--list-sinks")
            .output()
            .expect("failed to run pulsemixer");
        let listing = String::from_utf8_lossy(&output.stdout);

        let mpv_id = listing.lines().find_map(|l| parse_sink_input_id(l, "mpv"));
        let bbeats_id = listing
            .lines()
            .find_map(|l| parse_sink_input_id(l, "PipeWire ALSA [bbeats]"));

        if start.elapsed() > MAX_WAIT {
            panic!(
                "Timed out waiting for audio sink inputs — mpv found: {}, bbeats found: {}",
                mpv_id.is_some(),
                bbeats_id.is_some()
            );
        }

        let (Some(mpv_id), Some(bbeats_id)) = (mpv_id, bbeats_id) else {
            tokio::time::sleep(POLL_INTERVAL).await;
            continue;
        };

        let bbeats_vol = std::process::Command::new("pulsemixer")
            .args(["--id", &bbeats_id, "--get-volume"])
            .output()
            .expect("failed to get bbeats volume");
        let vol_str = String::from_utf8_lossy(&bbeats_vol.stdout);
        let bbeats_volume: u32 = vol_str
            .split_whitespace()
            .next()
            .expect("no volume value from pulsemixer")
            .parse()
            .expect("failed to parse bbeats volume");

        let target = (bbeats_volume as f64 * RATIO).round() as u32;
        println!(
            "Setting exam ambiance volume to {target}% (bbeats at {bbeats_volume}%, ratio {RATIO})"
        );

        let status = std::process::Command::new("pulsemixer")
            .args(["--id", &mpv_id, "--set-volume", &target.to_string()])
            .status()
            .expect("failed to set mpv volume");
        assert!(status.success(), "pulsemixer --set-volume failed");
        return Sinks { mpv: mpv_id, bbeats: bbeats_id };
    }
}

async fn setup_math(timer: Option<Option<timer::Countdown>>) {
    // tedi exposes the selected issue only through `open`; echo as $EDITOR prints its path
    let selected = std::process::Command::new("tedi")
        .args(["sprints", "selected", "open", "--offline"])
        .env("EDITOR", "echo")
        .output()
        .expect("failed to run tedi sprints selected open");
    assert!(selected.status.success(), "tedi sprints selected open failed: {}", String::from_utf8_lossy(&selected.stderr));
    let selected_out = String::from_utf8_lossy(&selected.stdout);
    let selected_path = selected_out.lines().next().expect("open prints the issue path first");
    if !selected_path.to_lowercase().contains("math") {
        eprintln!("tedi selected issue is not a math one: {selected_path}");
        eprintln!("Select it with `tedi sprints select` before running ambiance math.");
        std::process::exit(1);
    }

    let wallpaper = WallpaperGuard::capture();
    let mut ambiance = Ambiance::new(wallpaper);

    // networking roundtrip, run concurrently with rest of setup
    let mut tedi_resume = Command::new("tedi")
        .args(["-y", "sprints", "selected", "resume"])
        .stdin(Stdio::null())
        .spawn()
        .expect("failed to spawn tedi sprints selected resume");

    // Set wallpaper
    Command::new("swaymsg")
        .args([
            "output",
            "eDP-1",
            "bg",
            &format!("{}/.config/sway/wallpapers/MartinSchmid.jpeg", home()),
            "fill",
        ])
        .status()
        .await
        .expect("failed to set wallpaper");

    // Kill distractions
    kill_running_pp();
    for app in ["vesktop", "discord", "telegram-deskto"] {
        let _ = std::process::Command::new("pkill").arg(app).status();
    }

    // Start exam auditorium ambiance
    let child = Command::new("fish")
        .args([
            "-c",
            &format!("pp1 {}/Music/study/exam_auditorium_ambiance.mp3", home()),
        ])
        .process_group(0)
        .stdin(Stdio::null())
        .spawn()
        .expect("failed to start pp1");
    ambiance.own(child);

    // Start bbeats if not already running
    if !is_running("bbeats") {
        let child = Command::new("fish")
            .args(["-c", "bbeats"])
            .process_group(0)
            .stdin(Stdio::null())
            .spawn()
            .expect("failed to start bbeats");
        ambiance.own(child);
    } else {
        println!("bbeats already running, skipping");
    }

    // Wait for tedi resume to finish
    let status = tedi_resume
        .wait()
        .await
        .expect("failed to wait on tedi sprints selected resume");
    assert!(status.success(), "tedi sprints selected resume failed");

    // Balance volumes: set exam ambiance (mpv) to 87% of bbeats volume
    let sinks = balance_volumes().await;

    println!("Ambiance running.");
    match timer {
        Some(countdown) => timer::run(countdown, false, |paused| sinks.set_paused(paused)).expect("timer failed"), // returns on Ctrl-C
        None => match keys::Keys::grab().expect("failed to grab terminal") {
            Some(keys) => {
                let mut paused = false;
                loop {
                    match keys.next_within(std::time::Duration::from_secs(60)).expect("failed to read terminal") {
                        Some(keys::Key::TogglePause) => {
                            paused = !paused;
                            sinks.set_paused(paused);
                            print!("\r\x1b[K{}", if paused { "[paused]" } else { "" });
                            std::io::Write::flush(&mut std::io::stdout()).expect("stdout is the terminal");
                        }
                        Some(keys::Key::Quit) => break,
                        None => {}
                    }
                }
                if paused {
                    sinks.set_paused(false); // bbeats may outlive us
                }
            }
            None => signal::ctrl_c().await.expect("failed to listen for ctrl+c"),
        },
    }
    println!("\nTearing down...");
    drop(ambiance);
}

fn wait_for_window(app_id: &str, timeout_secs: u64) -> bool {
    let start = std::time::Instant::now();
    while start.elapsed() < std::time::Duration::from_secs(timeout_secs) {
        let output = std::process::Command::new("swaymsg")
            .args(["-t", "get_tree"])
            .output()
            .ok();
        if let Some(out) = output {
            let stdout = String::from_utf8_lossy(&out.stdout);
            if stdout.contains(&format!("\"app_id\": \"{}\"", app_id)) {
                return true;
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
    false
}

fn setup_math_firefox() {
    // Open YouTube video in Firefox (spawn, don't wait)
    let mut firefox = std::process::Command::new("firefox")
        .args(["https://www.youtube.com/watch?v=gnahH-iQLjQ"])
        .spawn()
        .expect("failed to launch firefox");
    std::thread::spawn(move || {
        let _ = firefox.wait();
    });

    // Wait for Firefox window to appear
    if !wait_for_window("firefox", 10) {
        eprintln!("Firefox window did not appear in time");
        return;
    }
    // Give window time to stabilize
    std::thread::sleep(std::time::Duration::from_millis(500));

    // Move the Firefox window to workspace 8 and switch to it
    let _ = std::process::Command::new("swaymsg")
        .args(["[app_id=firefox]", "move", "to", "workspace", "8"])
        .status();
    let _ = std::process::Command::new("swaymsg")
        .args(["workspace", "8"])
        .status();

    //XXX: wtype might not be the thing to use. And waiting 25s is fragile. So user should just press f manually.
    println!("Point at the video in ws8, and press 'f' to fullscreen and start.");
    //// Wait for YouTube to load, then press F to fullscreen and start video
    //thread::sleep(Duration::from_secs(25)); // spawning a new firefox + youtube instance can take ages, - make sure this is long enough
    //let _ = Command::new("wtype").args(["f"]).status();
}

#[tokio::main]
async fn main() {
    let mut args = Args::parse();
    if args.cont {
        args.timer = Some(Some(timer::Countdown::previous().unwrap_or_else(|e| {
            eprintln!("{e}");
            std::process::exit(1);
        })));
    }

    match args.command {
        Commands::MathFirefox => {
            assert!(args.timer.is_none(), "--timer is not supported for math-firefox");
            setup_math_firefox()
        }
        Commands::Math => setup_math(args.timer).await,
    }
}
