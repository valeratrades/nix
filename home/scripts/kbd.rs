#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
---

use std::env;
use std::process::Command;

// Default layouts with their variants: (layout, variant)
const DEFAULT_LAYOUTS: &[(&str, &str)] = &[("semimak", "ansi"), ("ru", "")];

fn map_layout(input: &str) -> &'static str {
    match input.to_lowercase().as_str() {
        "qwerty" | "us" => "us",
        "azerty" | "fr" => "fr",
        "qwertz" | "de" => "de",
        "dvorak" => "us",
        "colemak" => "us",
        "semimak" => "semimak",
        "ru" | "russian" => "ru",
        _ => Box::leak(input.to_lowercase().into_boxed_str()),
    }
}

fn map_variant(input: &str) -> &'static str {
    match input.to_lowercase().as_str() {
        "dvorak" => "dvorak",
        "colemak" => "colemak",
        _ => "",
    }
}

fn is_default_layout(layout: &str) -> bool {
    DEFAULT_LAYOUTS.iter().any(|(l, _)| *l == layout)
}

fn get_default_variant(layout: &str) -> &'static str {
    DEFAULT_LAYOUTS
        .iter()
        .find(|(l, _)| *l == layout)
        .map(|(_, v)| *v)
        .unwrap_or("")
}

fn get_current_layouts() -> Vec<String> {
    let output = Command::new("swaymsg")
        .args(["-t", "get_inputs", "--raw"])
        .output()
        .expect("Failed to run swaymsg");

    let json: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("Failed to parse swaymsg output");

    if let Some(inputs) = json.as_array() {
        for input in inputs {
            if let Some(names) = input.get("xkb_layout_names").and_then(|v| v.as_array()) {
                if !names.is_empty() {
                    return names
                        .iter()
                        .filter_map(|v| v.as_str())
                        .map(|s| layout_name_to_xkb(s))
                        .collect();
                }
            }
        }
    }
    DEFAULT_LAYOUTS.iter().map(|(l, _)| l.to_string()).collect()
}

fn layout_name_to_xkb(name: &str) -> String {
    match name.to_lowercase().as_str() {
        "semimak" | "semimak ansi" | "semimak iso" => "semimak".to_string(),
        "russian" => "ru".to_string(),
        "english (us)" | "english" => "us".to_string(),
        "french" => "fr".to_string(),
        "german" => "de".to_string(),
        _ => name.to_lowercase(),
    }
}

fn extract_base_layouts(current: &[String]) -> Vec<String> {
    if current.is_empty() {
        return DEFAULT_LAYOUTS.iter().map(|(l, _)| l.to_string()).collect();
    }

    if is_default_layout(&current[0]) {
        current.to_vec()
    } else {
        current[1..].to_vec()
    }
}

// Base xkb_options that should always be set
const BASE_XKB_OPTIONS: &str = "grp:win_space_toggle";

fn set_xkb_options(swap_ctrl_caps: bool) -> bool {
    let options = if swap_ctrl_caps {
        format!("{BASE_XKB_OPTIONS},ctrl:swapcaps")
    } else {
        BASE_XKB_OPTIONS.to_string()
    };
    let cmd = format!("input type:keyboard xkb_options \"{options}\"");
    Command::new("swaymsg")
        .arg(&cmd)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn set_layouts_with_variants(layouts: &[String], variants: &[String], swap_ctrl_caps: bool) -> bool {
    let layout_str = layouts.join(",");
    let variant_str = variants.join(",");

    // Clear variant first to avoid mismatched variant being applied during layout change
    let clear_variant_cmd = "input type:keyboard xkb_variant \"\"";
    let _ = Command::new("swaymsg").arg(clear_variant_cmd).status();

    let layout_cmd = format!("input type:keyboard xkb_layout \"{layout_str}\"");
    let variant_cmd = format!("input type:keyboard xkb_variant \"{variant_str}\"");

    let layout_ok = Command::new("swaymsg")
        .arg(&layout_cmd)
        .status()
        .map(|s| s.success())
        .unwrap_or(false);

    if !layout_ok {
        return false;
    }

    let variant_ok = Command::new("swaymsg")
        .arg(&variant_cmd)
        .status()
        .map(|s| s.success())
        .unwrap_or(false);

    if !variant_ok {
        return false;
    }

    // Set xkb_options based on whether we need to swap ctrl/caps
    // Non-default layouts need ctrl:swapcaps to undo keyd's swap
    set_xkb_options(swap_ctrl_caps)
}

fn switch_to_layout(index: usize) -> bool {
    let cmd = format!("input type:keyboard xkb_switch_layout {index}");
    Command::new("swaymsg")
        .arg(&cmd)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn build_variants(layouts: &[String], first_variant: &str) -> Vec<String> {
    // Variants are positional: variant[i] applies to layout[i]
    layouts
        .iter()
        .enumerate()
        .map(|(i, l)| {
            if i == 0 {
                first_variant.to_string()
            } else {
                get_default_variant(l).to_string()
            }
        })
        .collect()
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() != 2 {
        eprintln!("Usage: kbd <layout>");
        eprintln!("Examples: kbd qwerty, kbd azerty, kbd semimak, kbd ru");
        std::process::exit(1);
    }

    let input = &args[1];
    let requested = map_layout(input);
    let variant = map_variant(input);
    let current = get_current_layouts();
    let base = extract_base_layouts(&current);

    if is_default_layout(requested) {
        // Restore base layouts with their default variants
        let base_variants: Vec<String> = base
            .iter()
            .map(|l| get_default_variant(l).to_string())
            .collect();

        if current != base {
            // Default layouts don't need ctrl:swapcaps (keyd handles it)
            if !set_layouts_with_variants(&base, &base_variants, false) {
                eprintln!("Failed to restore base layouts");
                std::process::exit(1);
            }
        } else {
            // Even if layouts match, ensure xkb_options are correct
            set_xkb_options(false);
        }
        if let Some(idx) = base.iter().position(|l| l == requested) {
            if !switch_to_layout(idx) {
                eprintln!("Failed to switch to layout");
                std::process::exit(1);
            }
        }
        println!("Switched to: {requested}");
    } else {
        // Non-default layout: prepend to base
        let mut new_layouts = vec![requested.to_string()];
        new_layouts.extend(base.clone());

        let variants = build_variants(&new_layouts, variant);

        // Non-default layouts need ctrl:swapcaps to undo keyd's ctrl/caps swap
        if !set_layouts_with_variants(&new_layouts, &variants, true) {
            eprintln!("Failed to set layouts");
            std::process::exit(1);
        }
        switch_to_layout(0);
        let layouts_joined = new_layouts.join(",");
        println!("Set layouts: {layouts_joined}");
    }
}
