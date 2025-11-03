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

use clap::Parser;
use std::env;
use std::io::Write;
use std::process::{Command, Stdio};

/// Generate TOTP codes from environment variables
#[derive(Parser, Debug)]
#[command(name = "2fa")]
#[command(about = "Generate TOTP codes from environment variables")]
struct Args {
    /// Application name (reads {APP_NAME}_TOTP environment variable)
    app_name: String,

    /// Number of digits in the code (4-10)
    #[arg(default_value_t = 6)]
    digits: u32,

    /// Copy the code to clipboard
    #[arg(short, long)]
    copy: bool,
}

fn main() {
    let args = Args::parse();

    if !(4..=10).contains(&args.digits) {
        eprintln!("Invalid digits value. Use an integer between 4 and 10.");
        std::process::exit(1);
    }

    let app = &args.app_name;
    let digits = args.digits;

    let var = format!("{}_TOTP", app.to_uppercase());
    let mut secret = match env::var(&var) {
        Ok(v) if !v.trim().is_empty() => v,
        _ => {
            eprintln!("Environment variable {var} is not set.");
            std::process::exit(1);
        }
    };
    secret.retain(|c| !c.is_whitespace());

    let out = Command::new("oathtool")
        .args(["--base32", "--totp", &secret, "-d", &digits.to_string()])
        .output();

    let out = match out {
        Ok(o) if o.status.success() => o,
        Ok(o) => {
            let err = String::from_utf8_lossy(&o.stderr);
            eprintln!("oathtool failed: {err}");
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("Failed to run oathtool: {e}");
            std::process::exit(1);
        }
    };

    let code = String::from_utf8_lossy(&out.stdout).trim().to_string();

    if args.copy {
        let mut child = match Command::new("wl-copy").stdin(Stdio::piped()).spawn() {
            Ok(c) => c,
            Err(e) => {
                eprintln!("wl-copy not found or failed to start: {e}");
                std::process::exit(1);
            }
        };
        child.stdin.as_mut().unwrap().write_all(code.as_bytes()).unwrap();
        let _ = child.wait();
        println!("{code}\nCopied to clipboard.");
    } else {
        println!("{code}");
    }
}
