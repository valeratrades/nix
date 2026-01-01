#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::{Parser, Subcommand};
use std::process::{Command, Stdio};
use std::thread::sleep;
use std::time::Duration;

/// Known devices: (name, mac_address)
/// Uses dbus-send instead of bluetoothctl to avoid Adv Monitor spam
const KNOWN_DEVICES: &[(&str, &str)] = &[
    ("Soundcore Life Tune", "E8:EE:CC:36:53:49"),
    ("Philips SHB3075", "A4:77:58:82:26:43"),
    ("WH-1000XM4", "80:99:E7:D2:1F:51"),
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

fn mac_to_dbus_path(mac: &str) -> String {
    let mac_underscored = mac.replace(':', "_");
    format!("/org/bluez/hci0/dev_{mac_underscored}")
}

fn dbus_get_property(path: &str, interface: &str, property: &str) -> Option<String> {
    let output = Command::new("dbus-send")
        .args([
            "--system",
            "--dest=org.bluez",
            "--print-reply",
            path,
            "org.freedesktop.DBus.Properties.Get",
            &format!("string:{interface}"),
            &format!("string:{property}"),
        ])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    Some(String::from_utf8_lossy(&output.stdout).to_string())
}

fn dbus_call_method(path: &str, interface: &str, method: &str) -> bool {
    Command::new("dbus-send")
        .args([
            "--system",
            "--dest=org.bluez",
            "--print-reply",
            path,
            &format!("{interface}.{method}"),
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn bluetooth_powered() -> bool {
    dbus_get_property("/org/bluez/hci0", "org.bluez.Adapter1", "Powered")
        .map(|s| s.contains("boolean true"))
        .unwrap_or(false)
}

fn power_on_bluetooth() -> bool {
    println!("Turning on Bluetooth...");

    // Unblock bluetooth
    let _ = Command::new("sudo")
        .args(["rfkill", "unblock", "bluetooth"])
        .stderr(Stdio::null())
        .status();

    // Power on via dbus
    let _ = Command::new("dbus-send")
        .args([
            "--system",
            "--dest=org.bluez",
            "--print-reply",
            "/org/bluez/hci0",
            "org.freedesktop.DBus.Properties.Set",
            "string:org.bluez.Adapter1",
            "string:Powered",
            "variant:boolean:true",
        ])
        .stdout(Stdio::null())
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

fn is_device_connected(mac: &str) -> bool {
    let path = mac_to_dbus_path(mac);
    dbus_get_property(&path, "org.bluez.Device1", "Connected")
        .map(|s| s.contains("boolean true"))
        .unwrap_or(false)
}

fn get_battery_percentage(mac: &str) -> Option<u8> {
    let path = mac_to_dbus_path(mac);
    let output = dbus_get_property(&path, "org.bluez.Battery1", "Percentage")?;

    // Parse "variant byte 85" or similar
    for line in output.lines() {
        let line = line.trim();
        if line.starts_with("variant") && line.contains("byte") {
            if let Some(num_str) = line.split_whitespace().last() {
                return num_str.parse().ok();
            }
        }
    }
    None
}

fn connect_device(mac: &str) -> bool {
    let path = mac_to_dbus_path(mac);
    dbus_call_method(&path, "org.bluez.Device1", "Connect")
}

fn cmd_is_connected() -> Result<(), String> {
    for (_, mac) in KNOWN_DEVICES {
        if is_device_connected(mac) {
            match get_battery_percentage(mac) {
                Some(battery) => println!("{battery}"),
                None => println!("_"),
            }
            return Ok(());
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

    // Try to connect to each known device
    for (name, mac) in KNOWN_DEVICES {
        println!("Trying {name} ({mac})...");
        if connect_device(mac) {
            println!("Successfully connected to {name}");
            return Ok(());
        }
    }

    eprintln!("Could not connect to any known device");
    Err("No device connected".to_string())
}

fn cmd_off() -> Result<(), String> {
    println!("Turning off Bluetooth...");

    // Power off via dbus
    let _ = Command::new("dbus-send")
        .args([
            "--system",
            "--dest=org.bluez",
            "--print-reply",
            "/org/bluez/hci0",
            "org.freedesktop.DBus.Properties.Set",
            "string:org.bluez.Adapter1",
            "string:Powered",
            "variant:boolean:false",
        ])
        .stdout(Stdio::null())
        .status();

    let _ = Command::new("sudo")
        .args(["rfkill", "block", "bluetooth"])
        .stderr(Stdio::null())
        .status();

    // Verify it's off
    if bluetooth_powered() {
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
