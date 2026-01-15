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
    /// Set up ambiance for learning math
    Math,
}

fn main() {
    let args = Args::parse();

    match args.command {
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

fn setup_math() {
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
