#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
---

use std::env;
use std::process::Command;

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() != 2 {
        eprintln!("Usage: kbd <layout>");
        eprintln!("Example: kbd azerty");
        std::process::exit(1);
    }

    let layout = &args[1];

    // Use swaymsg to set the keyboard layout temporarily
    // This doesn't modify the config, so Win+Space will still cycle through configured layouts
    // Clear variant first, then set layout (must be separate commands)
    let variant_status = Command::new("swaymsg")
        .arg("input type:keyboard xkb_variant \"\"")
        .status();

    if let Err(e) = variant_status {
        eprintln!("Failed to run swaymsg: {}", e);
        std::process::exit(1);
    }

    let layout_cmd = format!("input type:keyboard xkb_layout {}", layout);
    let status = Command::new("swaymsg").arg(&layout_cmd).status();

    match status {
        Ok(s) if s.success() => {
            println!("Keyboard layout set to: {}", layout);
        }
        Ok(s) => {
            eprintln!("swaymsg failed with exit code: {:?}", s.code());
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("Failed to run swaymsg: {}", e);
            std::process::exit(1);
        }
    }
}
