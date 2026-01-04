#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
regex = "1"
---

use std::env;
use std::fs;
use std::process::Command;

// Default layouts with their variants: (layout, variant)
const DEFAULT_LAYOUTS: &[(&str, &str)] = &[("semimak", "ansi"), ("ru", "")];

//TODO: figure out auto switching back of Ctrl <-> Caps when switching to default layouts

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

const PATCHED_XKB_DIR: &str = "/tmp/kbd_xkb";
const CUSTOM_SYMBOLS_DIR: &str = "/home/v/nix/home/xkb_symbols";

/// Generate per-group ctrl/caps swap symbols
/// This creates a custom xkb symbols file that swaps ctrl/caps only for specified groups
fn generate_per_group_ctrl_swap(swap_groups: &[usize]) -> String {
    if swap_groups.is_empty() {
        return String::new();
    }

    let mut caps_symbols = Vec::new();
    let mut lctl_symbols = Vec::new();

    // Generate symbols for each group
    // Groups that need swap: CAPS -> Control_L, LCTL -> Caps_Lock
    // Groups that don't: leave as default (CAPS -> Caps_Lock, LCTL -> Control_L)
    for group in swap_groups {
        caps_symbols.push(format!("symbols[Group{group}]= [ Control_L ]"));
        lctl_symbols.push(format!("symbols[Group{group}]= [ Caps_Lock ]"));
    }

    format!(
        r#"
partial modifier_keys
xkb_symbols "pergroup_swapcaps" {{
    key <CAPS> {{
        type= "ONE_LEVEL",
        {}
    }};
    key <LCTL> {{
        type= "ONE_LEVEL",
        {}
    }};
}};
"#,
        caps_symbols.join(",\n        "),
        lctl_symbols.join(",\n        ")
    )
}

/// Generate a complete .xkb keymap file for the given layouts with ctrl:swapcaps on non-default ones
fn generate_xkb_file(layouts: &[String], variants: &[String]) -> Option<String> {
    // Create xkb directory structure with symbols subdirectory
    let symbols_dir = format!("{PATCHED_XKB_DIR}/symbols");
    fs::create_dir_all(&symbols_dir).ok()?;

    // Copy custom layouts (semimak, etc.) to symbols directory
    if let Ok(entries) = fs::read_dir(CUSTOM_SYMBOLS_DIR) {
        for entry in entries.flatten() {
            let src = entry.path();
            if src.is_file() {
                let dest = format!("{symbols_dir}/{}", entry.file_name().to_string_lossy());
                fs::copy(&src, &dest).ok();
            }
        }
    }

    // Determine which groups need ctrl/caps swap (non-default layouts)
    let swap_groups: Vec<usize> = layouts
        .iter()
        .enumerate()
        .filter(|(_, l)| !is_default_layout(l))
        .map(|(i, _)| i + 1) // xkb groups are 1-indexed
        .collect();

    // Generate and write per-group ctrl swap symbols
    let ctrl_swap_symbols = generate_per_group_ctrl_swap(&swap_groups);
    if !ctrl_swap_symbols.is_empty() {
        let ctrl_path = format!("{symbols_dir}/kbd_ctrl_swap");
        fs::write(&ctrl_path, &ctrl_swap_symbols).ok()?;
    }

    // Build xkb_symbols include string
    // Format: pc+layout1(variant1):1+layout2(variant2):2+...+inet(evdev)+group(win_space_toggle)
    let mut symbols_parts = vec!["pc".to_string()];

    for (i, layout) in layouts.iter().enumerate() {
        let variant = variants.get(i).map(|s| s.as_str()).unwrap_or("");
        let group_num = i + 1;

        let layout_spec = if variant.is_empty() {
            format!("{layout}:{group_num}")
        } else {
            format!("{layout}({variant}):{group_num}")
        };

        symbols_parts.push(layout_spec);
    }

    symbols_parts.push("inet(evdev)".to_string());

    // Add per-group ctrl swap if needed
    if !swap_groups.is_empty() {
        symbols_parts.push("kbd_ctrl_swap(pergroup_swapcaps)".to_string());
    }

    // Add group toggle option for all groups
    for i in 1..=layouts.len() {
        symbols_parts.push(format!("group(win_space_toggle):{i}"));
    }

    let symbols_include = symbols_parts.join("+");

    // Build complete keymap description
    let keymap = format!(
        r#"xkb_keymap {{
    xkb_keycodes  {{ include "evdev+aliases(qwerty)" }};
    xkb_types     {{ include "complete" }};
    xkb_compat    {{ include "complete" }};
    xkb_symbols   {{ include "{symbols_include}" }};
    xkb_geometry  {{ include "pc(pc105)" }};
}};
"#
    );

    let keymap_path = format!("{PATCHED_XKB_DIR}/keymap.xkbmap");
    let xkb_path = format!("{PATCHED_XKB_DIR}/keymap.xkb");

    fs::write(&keymap_path, &keymap).ok()?;

    // Compile with xkbcomp - use -xkb to output text-based XKB file
    // Use -I to add the patched xkb dir for custom symbols lookup
    let include_arg = format!("-I{PATCHED_XKB_DIR}");
    let compile_output = Command::new("xkbcomp")
        .args(["-xkb", &include_arg, &keymap_path, "-o", &xkb_path])
        .output()
        .ok()?;

    if !compile_output.status.success() {
        let stderr = String::from_utf8_lossy(&compile_output.stderr);
        eprintln!("xkbcomp failed: {stderr}");
        return None;
    }

    Some(xkb_path)
}

fn set_layouts_with_variants(layouts: &[String], variants: &[String]) -> bool {
    // Always use xkb_file approach to ensure consistent behavior
    // and proper ctrl:swapcaps handling for non-default layouts
    if let Some(xkb_path) = generate_xkb_file(layouts, variants) {
        let cmd = format!("input type:keyboard xkb_file \"{xkb_path}\"");
        return Command::new("swaymsg")
            .arg(&cmd)
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
    }

    // Fallback to regular method if xkb generation fails
    eprintln!("Warning: falling back to regular layout switching");
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

    Command::new("swaymsg")
        .arg(&variant_cmd)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
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
            if !set_layouts_with_variants(&base, &base_variants) {
                eprintln!("Failed to restore base layouts");
                std::process::exit(1);
            }
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

        if !set_layouts_with_variants(&new_layouts, &variants) {
            eprintln!("Failed to set layouts");
            std::process::exit(1);
        }
        switch_to_layout(0);
        let layouts_joined = new_layouts.join(",");
        println!("Set layouts: {layouts_joined}");
    }
}
