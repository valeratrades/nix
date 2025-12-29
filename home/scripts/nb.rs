#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::Parser;
use std::process::Command;

/// NixOS rebuild wrapper
#[derive(Parser, Debug)]
#[command(name = "nb")]
#[command(about = "NixOS rebuild wrapper with optional beep notifications")]
struct Args {
    /// Play beep sound before and after rebuild
    #[arg(short, long)]
    beep: bool,

    /// Enable debug mode with --show-trace and abort-on-warn
    #[arg(short = 'D', long)]
    debug: bool,

    /// Additional arguments to pass to nixos-rebuild
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    extra_args: Vec<String>,
}

fn main() {
    let args = Args::parse();

    // Get hostname
    let hostname_output = Command::new("hostname")
        .output()
        .expect("Failed to get hostname");
    let hostname = String::from_utf8_lossy(&hostname_output.stdout)
        .trim()
        .to_string();

    // Build the command
    let mut cmd = Command::new("sudo");
    cmd.args(["nixos-rebuild", "switch", "--impure", "--no-reexec"]);
    cmd.arg("--flake");
    cmd.arg(format!("/home/v/nix#{}", hostname));

    // Add debug flags if requested
    if args.debug {
        cmd.args(["--show-trace", "--option", "abort-on-warn", "true"]);
    }

    // Add extra arguments
    if !args.extra_args.is_empty() {
        cmd.args(&args.extra_args);
    }

    // Run the command
    let status = cmd.status().expect("Failed to run nixos-rebuild");
    let status_code = status.code().unwrap_or(1);

    // Play final beep if requested
    if args.beep {
        let _ = Command::new("beep")
            .arg(format!("nix rb {}", status_code))
            .status();
    }

    std::process::exit(status_code);
}
