#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---
// a thing to procedurally set up environment for performing distinctly different and cognitively demanding tasks

use clap::{Parser, Subcommand};
use std::process::Command;
use std::thread;
use std::time::Duration;

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

fn main() {
    let args = Args::parse();

    match args.command {
        Commands::MathFirefox => setup_math_firefox(),
        Commands::Math => setup_math(),
    }
}

fn wait_for_window(app_id: &str, timeout_secs: u64) -> bool {
    let start = std::time::Instant::now();
    while start.elapsed() < Duration::from_secs(timeout_secs) {
        let output = Command::new("swaymsg")
            .args(["-t", "get_tree"])
            .output()
            .ok();
        if let Some(out) = output {
            let stdout = String::from_utf8_lossy(&out.stdout);
            if stdout.contains(&format!("\"app_id\": \"{}\"", app_id)) {
                return true;
            }
        }
        thread::sleep(Duration::from_millis(200));
    }
    false
}

fn kill_running_pp() {
    // Kill mpv instances spawned by the `pp` fish function.
    // These have a distinctive flag combination: --no-terminal --no-video --loop-file --loop-playlist
    let output = Command::new("pgrep")
        .args(["-f", "mpv --no-terminal --no-video --loop-file --loop-playlist"])
        .output()
        .expect("failed to run pgrep");
    if output.status.success() {
        let pids = String::from_utf8_lossy(&output.stdout);
        for pid in pids.lines() {
            let pid = pid.trim();
            if !pid.is_empty() {
                println!("Killing pp instance (mpv pid {pid})");
                let _ = Command::new("kill").arg(pid).status();
            }
        }
    }
}

fn is_running(process_name: &str) -> bool {
    Command::new("pgrep")
        .args(["-x", process_name])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn setup_math() {
    // Set wallpaper
    let _ = Command::new("swaymsg")
        .args(["output", "eDP-1", "bg", &format!("{}/.config/sway/wallpapers/MartinSchmid.jpeg", std::env::var("HOME").expect("HOME not set")), "fill"])
        .status()
        .expect("failed to set wallpaper");

    // Kill any running pp instances
    kill_running_pp();

    // Start exam auditorium ambiance
    let mut child = Command::new("fish")
        .args(["-c", &format!("pp1 {}/Music/study/exam_auditorium_ambiance.mp3", std::env::var("HOME").expect("HOME not set"))])
        .spawn()
        .expect("failed to start pp1");
    thread::spawn(move || { let _ = child.wait(); });

    // Start bbeats if not already running
    if !is_running("bbeats") {
        let mut child = Command::new("fish")
            .args(["-c", "bbeats"])
            .spawn()
            .expect("failed to start bbeats");
        thread::spawn(move || { let _ = child.wait(); });
    } else {
        println!("bbeats already running, skipping");
    }
}

fn setup_math_firefox() {
    // Open YouTube video in Firefox (spawn, don't wait)
    let mut firefox = Command::new("firefox")
        .args(["https://www.youtube.com/watch?v=gnahH-iQLjQ"])
        .spawn()
        .expect("failed to launch firefox");
    thread::spawn(move || {
        let _ = firefox.wait();
    });

    // Wait for Firefox window to appear
    if !wait_for_window("firefox", 10) {
        eprintln!("Firefox window did not appear in time");
        return;
    }
    // Give window time to stabilize
    thread::sleep(Duration::from_millis(500));

    // Move the Firefox window to workspace 8 and switch to it
    let _ = Command::new("swaymsg")
        .args(["[app_id=firefox]", "move", "to", "workspace", "8"])
        .status();
    let _ = Command::new("swaymsg").args(["workspace", "8"]).status();

    //XXX: wtype might not be the thing to use. And waiting 25s is fragile. So user should just press f manually.
    println!("Point at the video in ws8, and press 'f' to fullscreen and start.");
    //// Wait for YouTube to load, then press F to fullscreen and start video
    //thread::sleep(Duration::from_secs(25)); // spawning a new firefox + youtube instance can take ages, - make sure this is long enough
    //let _ = Command::new("wtype").args(["f"]).status();
}
