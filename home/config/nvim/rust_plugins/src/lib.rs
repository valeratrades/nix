use nvim_oxi::{api, Array, Dictionary, Function, Object};
use std::process::Command;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use std::collections::HashMap;

/// Find all TODO comments in the project, sorted by number of '!' signs (descending)
fn find_todo_impl() {
    // Build the ripgrep + awk command
    // Count only '!' immediately after 'TODO' (e.g., TODO!!!, not TODO some text with !)
    let output = match Command::new("sh")
        .arg("-c")
        .arg(
            r#"rg --line-number -- "TODO" | awk -F: -v OFS=: '{match($0, /TODO!+/); count=RLENGTH-4; if(count<0) count=0; print count, $0}' | sort -rn"#,
        )
        .output()
    {
        Ok(o) if o.status.success() => o,
        Ok(_) => {
            let _ = api::err_writeln("No TODOs found");
            return;
        }
        Err(e) => {
            let _ = api::err_writeln(&format!("Error running search: {}", e));
            return;
        }
    };

    let stdout = String::from_utf8_lossy(&output.stdout);

    // Parse results into quickfix entries
    let mut qf_entries = Vec::new();

    for line in stdout.lines() {
        let parts: Vec<&str> = line.splitn(4, ':').collect();

        if parts.len() >= 4 {
            // parts[0] = count of '!' from awk (not used in quickfix)
            // parts[1] = filename
            // parts[2] = line number
            // parts[3] = content (everything after line number, includes column + text)

            let filename = parts[1].to_string();
            let lnum = parts[2].parse::<i64>().unwrap_or(0);
            let text = parts[3].to_string();

            let entry = Dictionary::from_iter([
                ("filename", Object::from(filename)),
                ("lnum", Object::from(lnum)),
                ("col", Object::from(0_i64)),
                ("text", Object::from(text)),
            ]);

            qf_entries.push(Object::from(entry));
        }
    }

    // Debug: print the first entry to see what we're passing
    if !qf_entries.is_empty() {
        let _ = api::err_writeln(&format!("DEBUG: First entry object: {:?}", qf_entries[0]));
    }

    // Set the quickfix list using vim.fn.setqflist (no second argument, just the list)
    let qf_array = Array::from_iter(qf_entries);

    // Try calling it and see exactly what the error is
    match api::call_function::<_, i64>("setqflist", (qf_array,)) {
        Ok(result) => {
            let _ = api::err_writeln(&format!("DEBUG: setqflist returned: {}", result));
        }
        Err(e) => {
            let _ = api::err_writeln(&format!("Error setting quickfix list: {}", e));
            return;
        }
    }

    // Set mark 'T' to allow jumping back
    if let Err(e) = api::command("mark T") {
        let _ = api::err_writeln(&format!("Error setting mark: {}", e));
    }
}

/// Check if Rust plugins need rebuilding
fn should_rebuild() -> bool {
    let config_dir = match std::env::var("XDG_CONFIG_HOME")
        .or_else(|_| std::env::var("HOME").map(|h| format!("{}/.config", h))) {
        Ok(dir) => PathBuf::from(dir).join("nvim/rust_plugins"),
        Err(_) => return true, // If can't determine, rebuild to be safe
    };

    let state_dir = match std::env::var("XDG_STATE_HOME")
        .or_else(|_| std::env::var("HOME").map(|h| format!("{}/.local/state", h))) {
        Ok(dir) => PathBuf::from(dir).join("nvim/rust_plugins"),
        Err(_) => return true,
    };

    let timestamp_file = state_dir.join("last_build");

    // Create state directory if needed
    let _ = fs::create_dir_all(&state_dir);

    // Get last build time
    let last_build_time = match fs::read_to_string(&timestamp_file) {
        Ok(contents) => match contents.trim().parse::<u64>() {
            Ok(time) => SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(time),
            Err(_) => return true,
        },
        Err(_) => return true, // No timestamp file, need to build
    };

    // Check if any files in rust_plugins were modified since last build
    fn check_dir_modified(dir: &Path, since: SystemTime) -> bool {
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();

                // Skip target directory and hidden files
                if path.file_name().and_then(|n| n.to_str())
                    .map(|n| n == "target" || n.starts_with('.'))
                    .unwrap_or(false) {
                    continue;
                }

                if path.is_file() {
                    if let Ok(metadata) = fs::metadata(&path) {
                        if let Ok(modified) = metadata.modified() {
                            if modified > since {
                                return true;
                            }
                        }
                    }
                } else if path.is_dir() {
                    if check_dir_modified(&path, since) {
                        return true;
                    }
                }
            }
        }
        false
    }

    check_dir_modified(&config_dir, last_build_time)
}

/// Trigger rebuild of Rust plugins if needed
fn rebuild_if_needed() {
    if !should_rebuild() {
        return;
    }

    let config_dir = match std::env::var("XDG_CONFIG_HOME")
        .or_else(|_| std::env::var("HOME").map(|h| format!("{}/.config", h))) {
        Ok(dir) => PathBuf::from(dir).join("nvim/rust_plugins"),
        Err(_) => return,
    };

    let state_dir = match std::env::var("XDG_STATE_HOME")
        .or_else(|_| std::env::var("HOME").map(|h| format!("{}/.local/state", h))) {
        Ok(dir) => PathBuf::from(dir).join("nvim/rust_plugins"),
        Err(_) => return,
    };

    let log_file = state_dir.join("build.log");
    let timestamp_file = state_dir.join("last_build");

    let start = std::time::Instant::now();

    // Run nix build
    let output = Command::new("sh")
        .arg("-c")
        .arg(format!("cd {} && nix build 2>&1", config_dir.display()))
        .output();

    let elapsed_ms = start.elapsed().as_millis();
    let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");

    match output {
        Ok(result) if result.status.success() => {
            // Log success
            let log_entry = format!("[{}] Rust plugin build SUCCESS ({}ms)\n", timestamp, elapsed_ms);
            let _ = fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(log_file)
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(log_entry.as_bytes())
                });

            // Update timestamp
            let _ = fs::write(timestamp_file, format!("{}", SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_secs()));
        }
        _ => {
            // Log failure
            let log_entry = format!("[{}] Rust plugin build FAILED ({}ms)\n", timestamp, elapsed_ms);
            let _ = fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(log_file)
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(log_entry.as_bytes())
                });
        }
    }
}

/// Parse a log line and extract destination and contents
/// Supports formats:
/// - `[indent] in [destination] with [contents]`
/// - `[indent] at [destination]`
/// - `[datetime] [LEVEL] [destination]: [contents]`
fn parse_log_line(log_line: String) -> (Option<String>, Option<String>) {
    // Pattern: "in [destination] with [contents]"
    if let Some(caps) = regex::Regex::new(r"in\s+([\w_:]+)\s+with\s+(.+)")
        .ok()
        .and_then(|re| re.captures(&log_line))
    {
        return (
            caps.get(1).map(|m| m.as_str().to_string()),
            caps.get(2).map(|m| m.as_str().to_string()),
        );
    }

    // Pattern: "at [destination.rs:line]"
    if let Some(caps) = regex::Regex::new(r"at\s+([\w_/]+\.rs:\d+)")
        .ok()
        .and_then(|re| re.captures(&log_line))
    {
        return (caps.get(1).map(|m| m.as_str().to_string()), None);
    }

    // Pattern: "YYYY-MM-DDTHH:MM:SS.sssZ LEVEL [destination]: [contents]"
    if let Some(caps) = regex::Regex::new(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z\s+[A-Z]+\s+([\w_:]+):\s+(.+)")
        .ok()
        .and_then(|re| re.captures(&log_line))
    {
        return (
            caps.get(1).map(|m| m.as_str().to_string()),
            caps.get(2).map(|m| m.as_str().to_string()),
        );
    }

    (None, None)
}

/// Prettify log contents using prettify_log and show in popup
fn popup_log_contents(contents: String) {
    // Check if prettify_log is available
    let check = Command::new("sh")
        .arg("-c")
        .arg("command -v prettify_log")
        .output();

    if check.map(|o| o.stdout.is_empty()).unwrap_or(true) {
        let _ = api::err_writeln("prettify_log not found in PATH. Install it from https://github.com/valeratrades/prettify_log");
        return;
    }

    // Escape single quotes in contents
    let escaped_contents = contents.replace("'", "'\\''");
    let prettify_cmd = format!(
        "sh -c 'cat <<EOF | prettify_log - --maybe-colon-nested\n{}\nEOF'",
        escaped_contents
    );

    let output = Command::new("sh")
        .arg("-c")
        .arg(&prettify_cmd)
        .output();

    match output {
        Ok(result) if result.status.success() => {
            let prettified = String::from_utf8_lossy(&result.stdout);
            let as_rust_block = format!("```rs\n{}```", prettified);

            // Call ShowMarkdownPopup via Lua
            let _ = api::call_function::<_, ()>(
                "luaeval",
                ("require('valera.utils').ShowMarkdownPopup(_A)", as_rust_block),
            );
        }
        _ => {
            let _ = api::err_writeln("Failed to run prettify_log");
        }
    }
}

/// VIM default keymaps by mode
fn vim_defaults() -> HashMap<&'static str, Vec<&'static str>> {
    let mut defaults = HashMap::new();

    defaults.insert("n", vec![
        "h", "j", "k", "l", "gj", "gk", "H", "M", "L", "w", "W", "e", "E", "b", "B", "ge", "gE",
        "%", "0", "^", "$", "g_", "gg", "G", "gd", "gD", "f", "F", "t", "T", ";", ",", "}", "{",
        "(", ")", "[", "]", "zz", "zt", "zb",
        "<C-e>", "<C-y>", "<C-b>", "<C-f>", "<C-d>", "<C-u>",
        "r", "R", "J", "gJ", "g~", "gu", "gU", "s", "S", "u", "U", "<C-r>", ".",
        "m", "`", "'", "<C-i>", "<C-o>", "<C-]>", "g,", "g;",
        "y", "d", "c", "p", "P", "gp", "gP", "x", "X", "Y", "D", "C",
        ">", "<", "=",
        "/", "?", "n", "N", "#", "*", "g*", "g#",
        "gt", "gT", "<C-w>",
        "a", "i", "o", "O", "I", "A",
        "v", "V", "<C-v>",
        "za", "zo", "zc", "zr", "zm", "zi", "zf", "zd",
        "K", "q", "@", "~", "!", ":", "<tab>", "<CR>", "gf", "gF", "<C-a>", "<C-x>", "ga", "gv", "gw",
    ]);

    defaults.insert("v", vec![
        "h", "j", "k", "l", "w", "W", "e", "E", "b", "B", "0", "^", "$",
        "gg", "G", "f", "F", "t", "T", ";", ",", "}", "{", "(", ")",
        "<C-d>", "<C-u>", "<C-f>", "<C-b>",
        "v", "V", "<C-v>", "o", "O",
        "aw", "ab", "aB", "at", "ib", "iB", "it", "a", "i",
        ">", "<", "y", "d", "c", "~", "u", "U", "r", "s", "x", "J", "gJ",
        "p", "P", ":", "n", "N", "*", "#",
    ]);

    defaults.insert("s", vec![
        "<C-g>", "c", "C", "d", "D", "y", "Y", "x", "X",
    ]);

    defaults.insert("o", vec![
        "h", "j", "k", "l", "w", "W", "e", "E", "b", "B",
        "f", "F", "t", "T", ";", ",", "0", "^", "$",
        "gg", "G", "}", "{", "(", ")", "[", "]",
        "a", "i",
        "v", "V", "<C-v>",
    ]);

    defaults.insert("i", vec![
        "<C-h>", "<C-w>", "<C-j>", "<C-t>", "<C-d>", "<C-n>", "<C-p>",
        "<C-r>", "<C-o>", "<C-a>", "<C-x>", "<C-e>", "<C-y>",
        "<Esc>", "<C-c>", "<C-[>",
    ]);

    defaults
}

/// Normalize key notation for comparison
fn normalize_key(key: &str) -> String {
    key.replace("<C-", "<c-")
        .replace("<c-", "<c-")
        .replace("<CR>", "<cr>")
}

/// Log to the rust plugins build log file
fn log_to_file(msg: &str) {
    let state_dir = match std::env::var("XDG_STATE_HOME")
        .or_else(|_| std::env::var("HOME").map(|h| format!("{}/.local/state", h))) {
        Ok(dir) => PathBuf::from(dir).join("nvim/rust_plugins"),
        Err(_) => return,
    };

    let log_file = state_dir.join("build.log");
    let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
    let log_entry = format!("[{}] {}\n", timestamp, msg);

    let _ = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_file)
        .and_then(|mut f| {
            use std::io::Write;
            f.write_all(log_entry.as_bytes())
        });
}

/// Log keymap calls to smart_keymap.log
fn log_keymap(msg: &str) {
    let state_dir = match std::env::var("XDG_STATE_HOME")
        .or_else(|_| std::env::var("HOME").map(|h| format!("{}/.local/state", h))) {
        Ok(dir) => PathBuf::from(dir).join("nvim/rust_plugins"),
        Err(_) => return,
    };

    let _ = fs::create_dir_all(&state_dir);
    let log_file = state_dir.join("smart_keymap.log");
    let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
    let log_entry = format!("[{}] {}\n", timestamp, msg);

    let _ = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_file)
        .and_then(|mut f| {
            use std::io::Write;
            f.write_all(log_entry.as_bytes())
        });
}

/// Smart keymap setter with validation and conflict checking
fn smart_keymap(mode: Object, lhs: nvim_oxi::String, rhs: Object, opts: Object) {
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

    // Expand modes - "" becomes ["n", "v", "s", "o"]
    let mut expanded_modes: Vec<&str> = Vec::new();
    for m in &mode_strings {
        if m.is_empty() {
            expanded_modes.extend(&["n", "v", "s", "o"]);
        } else {
            expanded_modes.push(m.as_str());
        }
    }

    // Get overwrite flag - check the string representation
    let overwrite = opts_dict.get("overwrite")
        .map(|o| {
            // The Object debug format shows "true" or "false" for booleans
            let debug_str = format!("{:?}", o);
            debug_str == "true"
        })
        .unwrap_or(false);

    // Check for conflicts
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
                lhs_str, mode_name, is_user_mapped, is_vim_default, overwrite));
            if !overwrite {
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
    if overwrite && !found_existing {
        let mode_str = expanded_modes.join(",");
        let _ = api::err_writeln(&format!(
            "[{}] Unnecessary overwrite=true: '{}' (mode '{}') has no existing mapping",
            caller_info, lhs_str, mode_str
        ));
    }

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

#[nvim_oxi::plugin]
fn rust_plugins() -> nvim_oxi::Result<Dictionary> {
    let find_todo = Function::from_fn(|()| find_todo_impl());
    let should_rebuild_fn = Function::from_fn(|()| should_rebuild());
    let rebuild_if_needed_fn = Function::from_fn(|()| rebuild_if_needed());
    let parse_log_line_fn = Function::from_fn(|(line,)| parse_log_line(line));
    let popup_log_contents_fn: Function<(String,), ()> = Function::from_fn(|(contents,)| popup_log_contents(contents));
    let smart_keymap_fn: Function<(Object, nvim_oxi::String, Object, Object), ()> =
        Function::from_fn(|(mode, lhs, rhs, opts)| smart_keymap(mode, lhs, rhs, opts));

    Ok(Dictionary::from_iter([
        ("find_todo", Object::from(find_todo)),
        ("should_rebuild", Object::from(should_rebuild_fn)),
        ("rebuild_if_needed", Object::from(rebuild_if_needed_fn)),
        ("parse_log_line", Object::from(parse_log_line_fn)),
        ("popup_log_contents", Object::from(popup_log_contents_fn)),
        ("smart_keymap", Object::from(smart_keymap_fn)),
    ]))
}
