#!/usr/bin/env -S rustup run nightly cargo -Zscript -q

use std::env;
use std::io::Write;
use std::process::{Command, Stdio};

fn main() {
    let mut copy = false;
    let mut pos: Vec<String> = Vec::new();

    for a in env::args().skip(1) {
        match a.as_str() {
            "-c" | "--copy" => copy = true,
            _ => pos.push(a),
        }
    }

    if pos.len() < 1 || pos.len() > 2 {
        eprintln!("Usage: 2fa [-c|--copy] <app_name> [digits]");
        std::process::exit(1);
    }

    let app = &pos[0];
    let digits = if pos.len() == 2 {
        match pos[1].parse::<u32>() {
            Ok(d) if (4..=10).contains(&d) => d,
            _ => {
                eprintln!("Invalid digits value. Use an integer between 4 and 10.");
                std::process::exit(1);
            }
        }
    } else {
        6
    };

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

    if copy {
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
