#!/usr/bin/env nix
---cargo
#! nix shell --impure --expr ``
#! nix let rust_flake = builtins.getFlake ''github:oxalica/rust-overlay'';
#! nix     nixpkgs_flake = builtins.getFlake ''nixpkgs'';
#! nix     pkgs = import nixpkgs_flake {
#! nix       system = builtins.currentSystem;
#! nix       overlays = [rust_flake.overlays.default];
#! nix     };
#! nix     toolchain = pkgs.rust-bin.nightly."2025-10-10".default.override { #TODO: switch to latest-nightly-with
#! nix       extensions = ["rust-src"];
#! nix     };
#! nix
#! nix in pkgs.symlinkJoin {
#! nix   name = "env";
#! nix   paths = [ toolchain pkgs.wtype ];
#! nix }
#! nix ``
#! nix --command sh -c ``cargo -Zscript -q "$0" "$@"``

[dependencies]
arboard = "3.6.1"
---


use arboard::Clipboard;
use std::process::{Command, exit};

/// Try to get clipboard text, first via wl-paste, then fall back to arboard
fn get_clipboard_text() -> Option<String> {
    // Try wl-paste first
    if let Ok(output) = Command::new("wl-paste").output() {
        if output.status.success() {
            if let Ok(text) = String::from_utf8(output.stdout) {
                let trimmed = text.trim();
                if !trimmed.is_empty() {
                    return Some(text);
                }
            }
        }
    }

    // Fall back to arboard
    if let Ok(mut clip) = Clipboard::new() {
        if let Ok(text) = clip.get_text() {
            let trimmed = text.trim();
            if !trimmed.is_empty() {
                return Some(text);
            }
        }
    }

    None
}

fn main() {
    // Try to read clipboard, first with wl-paste, then fall back to arboard
    let text = get_clipboard_text().unwrap_or_else(|| {
        eprintln!("Could not get clipboard contents or clipboard is empty");
        exit(1)
    });

    // Check if we have wtype available for Wayland
    let has_wtype = Command::new("which")
        .arg("wtype")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);

    if !has_wtype {
        eprintln!("Error: wtype not found. Please install wtype for Wayland keyboard simulation.");
        eprintln!("You can install it with: nix-shell -p wtype");
        exit(1);
    }

    // Use wtype with stdin (-) to type the text
    // This avoids issues with special characters in shell arguments
    use std::io::Write;
    use std::process::Stdio;

    let mut child = Command::new("wtype")
        .arg("-")
        .stdin(Stdio::piped())
        .spawn()
        .unwrap_or_else(|e| {
            eprintln!("Failed to execute wtype: {}", e);
            exit(1)
        });

    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(text.as_bytes()).unwrap_or_else(|e| {
            eprintln!("Failed to write to wtype stdin: {}", e);
            exit(1)
        });
    }

    let status = child.wait().unwrap_or_else(|e| {
        eprintln!("Failed to wait for wtype: {}", e);
        exit(1)
    });

    if !status.success() {
        eprintln!("wtype failed with exit code: {:?}", status.code());
        exit(1);
    }
}
