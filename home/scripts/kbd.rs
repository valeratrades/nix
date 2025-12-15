#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
---

use std::env;
use std::process::Command;

fn map_layout(input: &str) -> (&str, &str) {
    // Returns (layout, variant)
    // Maps friendly names to XKB layout names
    match input.to_lowercase().as_str() {
        "qwerty" | "us" => ("us", ""),
        "azerty" | "fr" => ("fr", ""),
        "qwertz" | "de" => ("de", ""),
        "dvorak" => ("us", "dvorak"),
        "colemak" => ("us", "colemak"),
        "semimak" => ("semimak", ""),
        "ru" | "russian" => ("ru", ""),
        _ => (input, ""), // Pass through as-is for custom/unknown layouts
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() != 2 {
        eprintln!("Usage: kbd <layout>");
        eprintln!("Examples: kbd qwerty, kbd azerty, kbd semimak, kbd us, kbd fr");
        std::process::exit(1);
    }

    let (layout, variant) = map_layout(&args[1]);

    // Use swaymsg to set the keyboard layout temporarily
    // This doesn't modify the config, so Win+Space will still cycle through configured layouts
    // Clear variant first, then set layout (must be separate commands)
    let variant_cmd = format!("input type:keyboard xkb_variant \"{}\"", variant);
    let variant_status = Command::new("swaymsg").arg(&variant_cmd).status();

    if let Err(e) = variant_status {
        eprintln!("Failed to run swaymsg: {}", e);
        std::process::exit(1);
    }

    let layout_cmd = format!("input type:keyboard xkb_layout {}", layout);
    let status = Command::new("swaymsg").arg(&layout_cmd).status();

    match status {
        Ok(s) if s.success() => {
            println!("Keyboard layout set to: {} (variant: {})", layout, if variant.is_empty() { "default" } else { variant });
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
