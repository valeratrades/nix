#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
tokio = { version = "1", features = ["full"] }
---
// a thing to procedurally set up environment for performing distinctly different and cognitively demanding tasks

use clap::{Parser, Subcommand};
use std::process::Stdio;
use tokio::process::Command;
use tokio::signal;

#[derive(Parser, Debug)]
#[command(name = "ambiance")]
#[command(about = "Set up work ambiance")]
struct Args {
    #[command(subcommand)]
    command: Commands,
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
    /// swaybg args to restore: Vec of ["-o", output, "-i", image, "-m", mode] groups
    restore_args: Vec<String>,
}

impl WallpaperGuard {
    fn capture() -> Self {
        // Parse all running swaybg processes to capture current wallpaper state
        let mut restore_args = Vec::new();
        let Ok(entries) = std::fs::read_dir("/proc") else {
            panic!("failed to read /proc");
        };
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
            if args.first().map(|s| s.contains("swaybg")).unwrap_or(false) {
                // skip the binary name, keep the rest
                restore_args = args[1..].to_vec();
                break;
            }
        }
        if restore_args.is_empty() {
            panic!("no swaybg process found to capture wallpaper state from");
        }
        Self { restore_args }
    }

    fn restore(&self) {
        use std::process::Command as StdCommand;
        // Kill any swaybg instances sway spawned for our override
        // Then re-launch swaybg with the original args
        // swaymsg output * bg ... would work but let's directly restore what was there
        let _ = StdCommand::new("swaybg")
            .args(&self.restore_args)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
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

    fn teardown(&mut self) {
        for child in &mut self.children {
            if let Some(pid) = child.id() {
                // kill the process group if we can, otherwise just the process
                unsafe { libc::kill(-(pid as i32), libc::SIGTERM) };
                let _ = child.start_kill();
            }
        }
        self.wallpaper.restore();
    }
}

// Needed for process group kills - link libc directly since we only need kill()
mod libc {
    unsafe extern "C" {
        pub fn kill(pid: i32, sig: i32) -> i32;
    }
    pub const SIGTERM: i32 = 15;
}

fn kill_running_pp() {
    // Kill mpv instances spawned by the `pp` fish function.
    // These have a distinctive flag combination: --no-terminal --no-video --loop-file --loop-playlist
    let output = std::process::Command::new("pgrep")
        .args(["-f", "mpv --no-terminal --no-video --loop-file --loop-playlist"])
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

async fn setup_math() {
    let wallpaper = WallpaperGuard::capture();
    let mut ambiance = Ambiance::new(wallpaper);

    // Set wallpaper
    Command::new("swaymsg")
        .args([
            "output", "eDP-1", "bg",
            &format!("{}/.config/sway/wallpapers/MartinSchmid.jpeg", home()),
            "fill",
        ])
        .status()
        .await
        .expect("failed to set wallpaper");

    // Kill any running pp instances
    kill_running_pp();

    // Start exam auditorium ambiance
    let child = Command::new("fish")
        .args(["-c", &format!("pp1 {}/Music/study/exam_auditorium_ambiance.mp3", home())])
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

    println!("Ambiance running. Ctrl+C to stop and restore.");
    signal::ctrl_c().await.expect("failed to listen for ctrl+c");
    println!("\nTearing down...");
    ambiance.teardown();
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
    let args = Args::parse();

    match args.command {
        Commands::MathFirefox => setup_math_firefox(),
        Commands::Math => setup_math().await,
    }
}
