#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
v_utils = { version = "2.20", default-features = false, features = ["io"] }
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
    let secret = match env::var(&var) {
        Ok(v) if !v.trim().is_empty() => v,
        _ => {
            eprintln!("Environment variable {var} is not set.");
            std::process::exit(1);
        }
    };

    let code = match v_utils::io::totp(&secret, digits) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{var} is not a base32 secret: {e}");
            std::process::exit(1);
        }
    };

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
