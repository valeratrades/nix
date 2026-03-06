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

    /// Toggle sccache in cargo config (true/false). If omitted, leaves current value.
    #[arg(long)]
    sccache: Option<bool>,

    /// Additional arguments to pass to nixos-rebuild
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    extra_args: Vec<String>,
}

fn set_nix_var(var: &str, value: &str) {
    let vars_path = "/home/v/nix/vars/default.nix";
    let content = std::fs::read_to_string(vars_path).expect("Failed to read vars/default.nix");

    let whoami = Command::new("whoami").output().expect("Failed to run whoami");
    let username = String::from_utf8_lossy(&whoami.stdout).trim().to_string();
    let username_marker = format!("username = \"{username}\";");

    let pattern = format!("{var} = ");
    let mut in_my_block = false;
    let mut depth: i32 = 0;
    let mut replaced = false;
    let new_content = content
        .lines()
        .map(|line| {
            let trimmed = line.trim();
            if trimmed.contains(&username_marker) {
                in_my_block = true;
                depth = 0;
            }
            if in_my_block {
                depth += trimmed.matches('{').count() as i32;
                depth -= trimmed.matches('}').count() as i32;
                if depth <= 0 && replaced {
                    in_my_block = false;
                }
            }
            let t = line.trim_start();
            if in_my_block && t.starts_with(&pattern) && !t.starts_with('#') {
                replaced = true;
                let indent = &line[..line.len() - t.len()];
                format!("{indent}{var} = {value};")
            } else {
                line.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
        + if content.ends_with('\n') { "\n" } else { "" };
    if !replaced {
        panic!("'{var}' not found in {vars_path} for user '{username}'");
    }
    std::fs::write(vars_path, new_content).expect("Failed to write vars/default.nix");
}

fn main() {
    let args = Args::parse();

    if let Some(v) = args.sccache {
        set_nix_var("sccache", if v { "true" } else { "false" });
    }

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
    cmd.arg(format!("/home/v/nix#{hostname}"));

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

    // Refresh shell init caches after successful rebuild
    if status.success() {
        eprintln!("Refreshing shell init caches...");
        let _ = Command::new("fish")
            .args(["-c", "refresh_shell_init_caches"])
            .status();
    }

    // Play final beep if requested
    if args.beep {
        let _ = Command::new("beep")
            .arg(format!("nix rb {status_code}"))
            .status();
    }

    std::process::exit(status_code);
}
