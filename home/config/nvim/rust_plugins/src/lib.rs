use nvim_oxi::{api, Array, Dictionary, Function, Object};
use std::process::Command;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

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

#[nvim_oxi::plugin]
fn rust_plugins() -> nvim_oxi::Result<Dictionary> {
    let find_todo = Function::from_fn(|()| find_todo_impl());
    let should_rebuild_fn = Function::from_fn(|()| should_rebuild());
    let rebuild_if_needed_fn = Function::from_fn(|()| rebuild_if_needed());

    Ok(Dictionary::from_iter([
        ("find_todo", Object::from(find_todo)),
        ("should_rebuild", Object::from(should_rebuild_fn)),
        ("rebuild_if_needed", Object::from(rebuild_if_needed_fn)),
    ]))
}
