use nvim_oxi::{api, Array, Dictionary, Object, String as NvimString};
use std::collections::HashMap;
use std::fs;

/// Feedkeys wrapper
/// Equivalent to `vim.api.nvim_feedkeys(s, mode, false)`
pub fn f(s: String, mode: Option<String>) {
    let mode_str = mode.unwrap_or_else(|| "n".to_string());
    let _ = api::feedkeys(&NvimString::from(s), &NvimString::from(mode_str), false);
}

/// Feedkeys with termcode replacement
/// Equivalent to `vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(s, true, true, true), mode, false)`
pub fn ft(s: String, mode: Option<String>) {
    let termcodes = api::replace_termcodes(s, true, true, true);
    let termcodes_str = termcodes.to_string_lossy().into_owned();
    f(termcodes_str, mode);
}

/// Get comment string for current buffer
pub fn infer_comment_string() -> String {
    // Check file extension
    let extension: String = api::call_function("expand", ("%:e",))
        .unwrap_or_else(|_| String::new());

    if extension == "lean" {
        return "--".to_string();
    }
    if extension == "html" {
        return "//".to_string();
    }

    // Get commentstring option
    let commentstring: String = api::get_option_value("commentstring", &Default::default())
        .unwrap_or_else(|_| "//".to_string());

    if commentstring.is_empty() {
        return "//".to_string();
    }

    // Remove " %s" suffix (last 3 chars)
    let without_percent_s = if commentstring.len() >= 3 {
        &commentstring[..commentstring.len() - 3]
    } else {
        &commentstring
    };

    // Strip whitespace
    without_percent_s.chars().filter(|c| !c.is_whitespace()).collect()
}

/// Log keymap info to ~/.local/state/nvim/rust_plugins/smart_keymap.log
fn log_keymap(msg: &str) {
    let state_dir = match std::env::var("XDG_STATE_HOME")
        .or_else(|_| std::env::var("HOME").map(|h| format!("{}/.local/state", h))) {
        Ok(dir) => std::path::PathBuf::from(dir).join("nvim/rust_plugins"),
        Err(_) => return,
    };

    let _ = fs::create_dir_all(&state_dir);
    let log_file = state_dir.join("smart_keymap.log");

    use std::io::Write;
    let _ = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_file)
        .and_then(|mut f| f.write_all(format!("{}\n", msg).as_bytes()));
}

/// Normalize a key for comparison (handle case, <C-*> vs <c-*>, etc)
fn normalize_key(key: &str) -> String {
    key.to_lowercase()
        .replace("<c-", "<C-")
        .replace("<m-", "<M-")
        .replace("<a-", "<A-")
}

/// Return vim default keymaps
fn vim_defaults() -> HashMap<&'static str, Vec<&'static str>> {
    let mut map = HashMap::new();

    // Normal mode
    map.insert("n", vec![
        // Movement
        "h", "j", "k", "l", "gj", "gk", "H", "M", "L",
        "w", "W", "e", "E", "b", "B", "ge", "gE",
        "%", "0", "^", "$", "g_", "gg", "G",
        "gd", "gD", "f", "F", "t", "T", ";", ",",
        "}", "{", "(", ")", "[", "]",
        "zz", "zt", "zb",
        // Scrolling
        "<C-e>", "<C-y>", "<C-b>", "<C-f>", "<C-d>", "<C-u>",
        // Editing
        "r", "R", "J", "gJ", "g~", "gu", "gU", "s", "S", "u", "U", "<C-r>", ".",
        // Marks/Jumps
        "m", "`", "'", "<C-i>", "<C-o>", "<C-]>", "g,", "g;",
        // Operators
        "y", "d", "c", "p", "P", "gp", "gP", "x", "X", "Y", "D", "C",
        // Indent
        ">", "<", "=",
        // Search
        "/", "?", "n", "N", "#", "*", "g*", "g#",
        // Tabs/Windows
        "gt", "gT", "<C-w>",
        // Text entry
        "a", "i", "o", "O", "I", "A",
        // Visual
        "v", "V", "<C-v>",
        // Folds
        "za", "zo", "zc", "zr", "zm", "zi", "zf", "zd",
        // Other
        "K", "q", "@", "~", "!", ":", "<tab>", "<CR>", "gf", "gF",
        "<C-a>", "<C-x>", "ga", "gv", "gw",
    ]);

    // Visual mode
    map.insert("v", vec![
        // Movement
        "h", "j", "k", "l", "w", "W", "e", "E", "b", "B",
        "0", "^", "$", "gg", "G",
        "f", "F", "t", "T", ";", ",",
        "}", "{", "(", ")",
        "<C-d>", "<C-u>", "<C-f>", "<C-b>",
        // Visual
        "v", "V", "<C-v>", "o", "O",
        // Text objects
        "aw", "ab", "aB", "at", "ib", "iB", "it", "a", "i",
        // Indent
        ">", "<",
        // Operators
        "y", "d", "c", "~", "u", "U", "r", "s", "x", "J", "gJ", "p", "P",
        // Other
        ":", "n", "N", "*", "#",
    ]);

    // Visual-line mode (x) - same as visual
    map.insert("x", vec![
        "h", "j", "k", "l", "w", "W", "e", "E", "b", "B",
        "0", "^", "$", "gg", "G",
        "f", "F", "t", "T", ";", ",",
        "}", "{", "(", ")",
        "<C-d>", "<C-u>", "<C-f>", "<C-b>",
        "v", "V", "<C-v>", "o", "O",
        "aw", "ab", "aB", "at", "ib", "iB", "it", "a", "i",
        ">", "<",
        "y", "d", "c", "~", "u", "U", "r", "s", "x", "J", "gJ", "p", "P",
        ":", "n", "N", "*", "#",
    ]);

    // Select mode
    map.insert("s", vec![
        "<C-g>", "c", "C", "d", "D", "y", "Y", "x", "X",
    ]);

    // Operator-pending mode
    map.insert("o", vec![
        "h", "j", "k", "l", "w", "W", "e", "E", "b", "B",
        "f", "F", "t", "T", ";", ",",
        "0", "^", "$", "gg", "G",
        "}", "{", "(", ")", "[", "]",
        "a", "i", "v", "V", "<C-v>",
    ]);

    // Insert mode
    map.insert("i", vec![
        "<C-h>", "<C-w>", "<C-j>", "<C-t>", "<C-d>",
        "<C-n>", "<C-p>", "<C-r>", "<C-o>",
        "<C-a>", "<C-x>", "<C-e>", "<C-y>",
        "<Esc>", "<C-c>", "<C-[>",
    ]);

    // Lang-Arg (l) mode - empty for now
    map.insert("l", vec![]);

    // Command mode
    map.insert("c", vec![
        "<C-b>", "<C-e>", "<C-f>",
        "<C-h>", "<C-w>", "<C-u>",
        "<C-n>", "<C-p>", "<C-r>",
    ]);

    // Terminal mode - empty for now
    map.insert("t", vec!["<C-w>s"]);

    map
}

/// Smart keymap that validates mappings and warns about conflicts
///
/// # Options
///
/// * `overwrite` - `Option<bool>`:
///   - `Some(true)`: Explicitly allow overwriting existing mappings (skips conflict warnings)
///   - `Some(false)`: Warn about conflicts with existing mappings
///   - `None`: Skip the overwrite evaluation entirely (useful for performance)
///
///   **WARNING**: Using `overwrite = nil` should be avoided if possible, as it bypasses
///   safety checks that prevent accidental keymap conflicts. Only use when you're certain
///   the mapping doesn't conflict or when performance is critical.
pub fn smart_keymap(mode: Object, lhs: nvim_oxi::String, rhs: Object, opts: Object) {
    let lhs_str = lhs.to_string_lossy();

    // Parse opts dictionary
    let opts_dict: Dictionary = match opts.clone().try_into() {
        Ok(d) => d,
        Err(_) => Dictionary::new(),
    };

    // Get caller info from opts (passed by Lua wrapper)
    let caller_info: String = opts_dict.get("_caller")
        .and_then(|o| {
            let s: Result<nvim_oxi::String, _> = o.clone().try_into();
            s.ok()
        })
        .map(|s: nvim_oxi::String| s.to_string_lossy().into())
        .unwrap_or_else(|| "unknown:0".to_string());

    // Log the call for debugging
    log_keymap(&format!("smart_keymap called from {}: lhs='{}', mode={:?}, opts={:?}", caller_info, lhs_str, mode, opts_dict));

    // Check for desc
    if opts_dict.get("desc").is_none() {
        let _ = api::err_writeln(&format!("[{}] Keymap '{}' missing desc (required for which-key)", caller_info, lhs_str));
    }

    // Parse mode - handle both string and array, store as String for later use
    let mode_strings: Vec<String> = match mode.clone() {
        obj => {
            // Try as string first
            let s_result: Result<nvim_oxi::String, _> = obj.clone().try_into();
            if let Ok(s) = s_result {
                vec![s.to_string_lossy().into()]
            } else {
                // Fall back to checking via Lua
                let lua_check = "return type(_A) == 'table' and _A or {_A}";
                let result: Array = api::call_function("luaeval", (lua_check, obj))
                    .unwrap_or_else(|_| Array::from_iter(vec![Object::from("n")]));

                result.into_iter()
                    .filter_map(|o| {
                        let s: Result<nvim_oxi::String, _> = o.try_into();
                        s.ok()
                    })
                    .map(|s: nvim_oxi::String| s.to_string_lossy().into())
                    .collect()
            }
        }
    };

    // expand "" to all modes it actually contains
    let mut expanded_modes: Vec<&str> = Vec::new();
    for m in &mode_strings {
        if m.is_empty() {
            expanded_modes.extend(&["n", "v", "x", "s", "o", "i", "l", "c", "t"]);
        } else {
            expanded_modes.push(m.as_str());
        }
    }

    // Get overwrite flag - now Option<bool>
    // None (nil in Lua) means skip the evaluation entirely
    // Some(true) means explicitly allow overwriting
    // Some(false) means warn about conflicts (default behavior)
    let overwrite: Option<bool> = opts_dict.get("overwrite")
        .map(|o| {
            // The Object debug format shows "true" or "false" for booleans
            let debug_str = format!("{:?}", o);
            debug_str == "true"
        });

    // Check for conflicts (skip if overwrite is None/nil)
    if let Some(overwrite_value) = overwrite {
        let vim_defs = vim_defaults();
        let normalized_lhs = normalize_key(&lhs_str);
        let mut found_existing = false;

        for mode_name in &expanded_modes {
            // Check user-defined mappings (maparg returns dict if mapping exists)
            let maparg_result: Dictionary = api::call_function(
                "maparg",
                (lhs.clone(), &mode_name[..], false, true)
            ).unwrap_or_else(|_| Dictionary::new());

            // Check if there's an existing user/plugin mapping
            // maparg returns non-empty dict with lhs field if mapping exists
            let is_user_mapped = !maparg_result.is_empty() &&
                maparg_result.get("lhs")
                    .and_then(|o| {
                        let s: Result<nvim_oxi::String, _> = o.clone().try_into();
                        s.ok()
                    })
                    .map(|s: nvim_oxi::String| s.to_string_lossy() == lhs_str)
                    .unwrap_or(false);

            // Check vim defaults (with normalized comparison)
            let empty_vec = vec![];
            let defaults_for_mode = vim_defs.get(&mode_name[..]).unwrap_or(&empty_vec);
            let is_vim_default = defaults_for_mode.iter()
                .any(|key| normalize_key(key) == normalized_lhs);

            if is_user_mapped || is_vim_default {
                found_existing = true;
                log_keymap(&format!("Found existing mapping for '{}' in mode '{}': is_user_mapped={}, is_vim_default={}, overwrite={}",
                    lhs_str, mode_name, is_user_mapped, is_vim_default, overwrite_value));
                if !overwrite_value {
                    let source = if is_user_mapped { "user mapping" } else { "vim default" };
                    let msg = format!(
                        "[{}] Keymap conflict: '{}' (mode '{}') overwrites {}. Pass overwrite = true if intentional.",
                        caller_info, lhs_str, mode_name, source
                    );
                    log_keymap(&msg);
                    let _ = api::err_writeln(&msg);
                }
            }
        }

        // Warn if overwrite=true but nothing exists
        if overwrite_value && !found_existing {
            let mode_str = expanded_modes.join(",");
            let _ = api::err_writeln(&format!(
                "[{}] Unnecessary overwrite=true: '{}' (mode '{}') has no existing mapping",
                caller_info, lhs_str, mode_str
            ));
        }
    }
    // If overwrite is None, we skip the entire conflict evaluation

    // Build final opts - remove overwrite and _caller, set noremap default
    let mut final_opts = Dictionary::new();
    let mut has_noremap = false;

    for (key, value) in opts_dict.iter() {
        let key_str = key.to_string_lossy();
        if key_str == "noremap" {
            has_noremap = true;
        }
        if key_str != "overwrite" && key_str != "_caller" {
            final_opts.insert(key_str.as_ref(), value.clone());
        }
    }

    if !has_noremap {
        final_opts.insert("noremap", Object::from(true));
    }

    // Call vim.keymap.set
    let lua_call = "vim.keymap.set(_A[1], _A[2], _A[3], _A[4])";
    let args = Array::from_iter(vec![mode, Object::from(lhs), rhs, Object::from(final_opts)]);
    let _ = api::call_function::<_, ()>("luaeval", (lua_call, args));
}
