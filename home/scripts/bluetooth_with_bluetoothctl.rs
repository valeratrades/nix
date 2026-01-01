#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::{Parser, Subcommand};
use std::process::{Command, Stdio};
use std::thread::sleep;
use std::time::Duration;

/// Known devices: (name, Option<mac_address>)
/// If mac is None, we search by name in paired devices
const KNOWN_DEVICES: &[(&str, Option<&str>)] = &[
    ("Soundcore Life Tune", Some("E8:EE:CC:36:53:49")),
    ("Philips SHB3075", Some("A4:77:58:82:26:43")),
    ("WH-1000XM4", Some("80:99:E7:D2:1F:51")),
    ("WH-CH520", None),
];

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
    /// Check if any known device is connected and print battery percentage
    IsConnected,
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

fn get_device_info(mac: &str) -> Option<String> {
    let output = Command::new("bluetoothctl")
        .args(["info", mac])
        .output()
        .ok()?;
    Some(String::from_utf8_lossy(&output.stdout).to_string())
}

fn is_device_connected(mac: &str) -> bool {
    get_device_info(mac)
        .map(|info| info.contains("Connected: yes"))
        .unwrap_or(false)
}

fn get_battery_percentage(mac: &str) -> Option<u8> {
    let info = get_device_info(mac)?;
    for line in info.lines() {
        if line.contains("Battery Percentage") {
            // Format: "	Battery Percentage: 0x55 (85)"
            if let Some(start) = line.find('(') {
                if let Some(end) = line.find(')') {
                    return line[start + 1..end].parse().ok();
                }
            }
        }
    }
    None
}

fn resolve_mac(name: &str, known_mac: Option<&str>) -> Option<String> {
    if let Some(mac) = known_mac {
        return Some(mac.to_string());
    }
    // Search in paired devices by name
    let paired = get_paired_devices();
    for (mac, device_name) in paired {
        if device_name.to_lowercase().contains(&name.to_lowercase()) {
            return Some(mac);
        }
    }
    None
}

fn cmd_is_connected() -> Result<(), String> {
    for (name, known_mac) in KNOWN_DEVICES {
        if let Some(mac) = resolve_mac(name, *known_mac) {
            if is_device_connected(&mac) {
                match get_battery_percentage(&mac) {
                    Some(battery) => println!("{battery}"),
                    None => println!("_"), //HACK: some l
                }
                return Ok(());
            }
        }
    }
    Ok(())
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

    // Try to connect to each known device
    for (name, known_mac) in KNOWN_DEVICES {
        if let Some(mac) = known_mac {
            // Direct MAC address known
            println!("Trying {name} ({mac})...");
            if connect_device(mac) {
                println!("Successfully connected to {name}");
                return Ok(());
            }
        } else {
            // Search by name
            for (mac, device_name) in &all_devices {
                if device_name.to_lowercase().contains(&name.to_lowercase()) {
                    println!("Found {device_name} ({mac}), attempting to connect...");
                    if connect_device(mac) {
                        println!("Successfully connected to {device_name}");
                        return Ok(());
                    } else {
                        println!("Failed to connect to {device_name}");
                    }
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

    let known_names: Vec<_> = KNOWN_DEVICES.iter().map(|(n, _)| *n).collect();
    eprintln!("Could not connect to any of: {known_names:?}");
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
        Commands::IsConnected => cmd_is_connected(),
    };

    if let Err(e) = result {
        eprintln!("Error: {e}");
        std::process::exit(1);
    }
}
