#!/usr/bin/env nix
---cargo
#! nix shell --impure --expr ``
#! nix let rust_flake = builtins.getFlake ''github:oxalica/rust-overlay'';
#! nix     nixpkgs_flake = builtins.getFlake ''nixpkgs'';
#! nix     pkgs = import nixpkgs_flake {
#! nix       system = builtins.currentSystem;
#! nix       overlays = [rust_flake.overlays.default];
#! nix     };
#! nix     toolchain = pkgs.rust-bin.nightly."2025-10-10".default.override {
#! nix       extensions = ["rust-src"];
#! nix     };
#! nix
#! nix in toolchain
#! nix ``
#! nix --command sh -c ``cargo -Zscript -q "$0" "$@"``

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::{Parser, Subcommand};
use std::process::{Command, Stdio};
use std::thread::sleep;
use std::time::Duration;

//TODO: standardize an env var with ;-separated list of "name-id" for each device
const DEVICE_NAMES: &[&str] = &["WH-1000XM4"];

#[derive(Parser, Debug)]
#[command(name = "bluetooth")]
#[command(about = "Bluetooth management utilities")]
struct Args {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Connect to known headphones
    Headphones,
    /// Turn off Bluetooth
    Off,
}

fn bluetooth_powered() -> bool {
    let output = Command::new("bluetoothctl")
        .arg("show")
        .output()
        .expect("Failed to run bluetoothctl show");
    String::from_utf8_lossy(&output.stdout).contains("Powered: yes")
}

fn power_on_bluetooth() -> bool {
    println!("Turning on Bluetooth...");

    // Unblock bluetooth
    let _ = Command::new("sudo")
        .args(["rfkill", "unblock", "bluetooth"])
        .stderr(Stdio::null())
        .status();

    // Power on
    let _ = Command::new("bluetoothctl")
        .args(["power", "on"])
        .stderr(Stdio::null())
        .status();

    // Wait for adapter to be ready (up to 5 seconds)
    for _ in 0..10 {
        if bluetooth_powered() {
            return true;
        }
        sleep(Duration::from_millis(500));
    }

    false
}

fn get_paired_devices() -> Vec<(String, String)> {
    let output = Command::new("bluetoothctl")
        .arg("devices")
        .output()
        .expect("Failed to run bluetoothctl devices");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut devices = Vec::new();

    for line in stdout.lines() {
        // Format: "Device XX:XX:XX:XX:XX:XX Device Name"
        let parts: Vec<&str> = line.splitn(3, ' ').collect();
        if parts.len() >= 3 {
            let mac = parts[1].to_string();
            let name = parts[2].to_string();
            devices.push((mac, name));
        }
    }

    devices
}

fn connect_device(mac: &str) -> bool {
    let status = Command::new("bluetoothctl")
        .args(["connect", mac])
        .status()
        .expect("Failed to run bluetoothctl connect");
    status.success()
}

fn cmd_headphones() -> Result<(), String> {
    // Ensure Bluetooth is powered on
    if !bluetooth_powered() {
        if !power_on_bluetooth() {
            return Err("Failed to power on Bluetooth adapter".to_string());
        }
    }

    // Get list of paired devices
    let all_devices = get_paired_devices();

    // Try to connect to each device by name
    for pattern in DEVICE_NAMES {
        for (mac, name) in &all_devices {
            if name.to_lowercase().contains(&pattern.to_lowercase()) {
                println!("Found {} ({}), attempting to connect...", name, mac);
                if connect_device(mac) {
                    println!("Successfully connected to {}", name);
                    return Ok(());
                } else {
                    println!("Failed to connect to {}", name);
                }
            }
        }
    }

    if all_devices.is_empty() {
        eprintln!("No paired devices found. Pair your headphones first:");
        eprintln!("  bluetoothctl scan on");
        eprintln!("  bluetoothctl pair <MAC>");
        eprintln!("  bluetoothctl trust <MAC>");
        return Err("No paired devices".to_string());
    }

    eprintln!("Could not find any of: {:?}", DEVICE_NAMES);
    eprintln!("Available paired devices:");
    for (mac, name) in &all_devices {
        eprintln!("  {mac} - {name}");
    }
    Err("Headphones not in paired devices".to_string())
}

fn cmd_off() -> Result<(), String> {
    println!("Turning off Bluetooth...");

    let _ = Command::new("bluetoothctl")
        .args(["power", "off"])
        .stderr(Stdio::null())
        .status();

    let _ = Command::new("sudo")
        .args(["rfkill", "block", "bluetooth"])
        .stderr(Stdio::null())
        .status();

    // Verify it's off
    let output = Command::new("bluetoothctl")
        .arg("show")
        .output()
        .expect("Failed to run bluetoothctl show");

    if !String::from_utf8_lossy(&output.stdout).contains("Powered: no") {
        return Err("Failed to power off Bluetooth adapter".to_string());
    }

    println!("Bluetooth powered off successfully");
    Ok(())
}

fn main() {
    let args = Args::parse();

    let result = match args.command {
        Commands::Headphones => cmd_headphones(),
        Commands::Off => cmd_off(),
    };

    if let Err(e) = result {
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }
}
