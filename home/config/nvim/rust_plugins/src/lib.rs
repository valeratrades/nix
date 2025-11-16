use nvim_oxi::{api, Array, Dictionary, Function, Object};
use std::process::Command;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

mod comment;
mod shorthands;
mod remap;
mod lsp;
mod utils;

/// Find all TODO comments in the project, sorted by number of '!' signs (descending)
///
/// Note: To prevent a line containing "TODO" from being parsed as a TODO comment,
/// use Russian О (Cyrillic) instead of English O: TОDO
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

    // Set the quickfix list using vim.fn.setqflist (no second argument, just the list)
    let qf_array = Array::from_iter(qf_entries);

    if let Err(e) = api::call_function::<_, i64>("setqflist", (qf_array,)) {
        let _ = api::err_writeln(&format!("Error setting quickfix list: {}", e));
        return;
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
    // Notify user that rebuild is starting
    let _ = api::err_writeln("Rebuilding Rust plugins...");

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

/// Go to file:line:col or function symbol
/// Supports formats:
/// - file:line:col
/// - file:line
/// - file::mod::function (LSP symbol path)
/// - file (just open the file)
fn goto_file_line_column_or_function(file_line_or_func: String) {
    use regex::Regex;

    // Check for file:line:col pattern
    if let Some(caps) = Regex::new(r"^([^:]+):(\d+):(\d+)$")
        .ok()
        .and_then(|re| re.captures(&file_line_or_func))
    {
        let file = caps.get(1).unwrap().as_str();
        let line: i64 = caps.get(2).unwrap().as_str().parse().unwrap_or(1);
        let col: i64 = caps.get(3).unwrap().as_str().parse().unwrap_or(1);

        let _ = api::command(&format!("edit {}", file));
        let _ = api::call_function::<_, ()>("cursor", (line, col));
        let _ = api::command("normal! zz");
        return;
    }

    // Check for file:line pattern (without col)
    if let Some(caps) = Regex::new(r"^([^:]+):(\d+)$")
        .ok()
        .and_then(|re| re.captures(&file_line_or_func))
    {
        let file = caps.get(1).unwrap().as_str();
        let line: i64 = caps.get(2).unwrap().as_str().parse().unwrap_or(1);

        let _ = api::command(&format!("edit {}", file));
        let _ = api::call_function::<_, ()>("cursor", (line, 1_i64));
        let _ = api::command("normal! zz");
        return;
    }

    // Check for LSP symbol path (contains "::")
    if file_line_or_func.contains("::") {
        // Extract the last segment as the function name
        let function_name = file_line_or_func
            .split("::")
            .last()
            .unwrap_or(&file_line_or_func);

        // Check if LSP is active
        let lsp_clients: Array = api::call_function("luaeval", ("vim.lsp.get_clients()",))
            .unwrap_or_else(|_| Array::new());

        if !lsp_clients.is_empty() {
            // Use Telescope LSP workspace symbols
            let lua_code = format!(
                r#"
                local builtin = require('telescope.builtin')
                local actions = require('telescope.actions')
                builtin.lsp_workspace_symbols({{
                    query = '{}',
                    symbols = {{ 'function', 'method' }},
                    on_complete = {{
                        function(picker)
                            actions.select_default(picker.prompt_bufnr)
                            vim.cmd("normal! zt")
                            vim.defer_fn(function()
                                vim.cmd("stopinsert")
                            end, 30)
                        end,
                    }},
                }})
                "#,
                function_name
            );
            let _ = api::call_function::<_, ()>("luaeval", (lua_code,));
        } else {
            let _ = api::err_writeln("No LSP clients found. Falling back to live_grep");
            let lua_code = format!(
                r#"
                local builtin = require('telescope.builtin')
                builtin.live_grep({{
                    default_text = '{}\\(',
                    hidden = true,
                    no_ignore = true,
                    file_ignore_patterns = {{ '.git/', 'target/', '%.lock' }}
                }})
                "#,
                function_name
            );
            let _ = api::call_function::<_, ()>("luaeval", (lua_code,));
        }
        return;
    }

    // Just a file path
    let expanded_file: String = api::call_function("expand", (file_line_or_func.clone(),))
        .unwrap_or(file_line_or_func);

    let is_readable: i64 = api::call_function("filereadable", (expanded_file.clone(),))
        .unwrap_or(0);

    if is_readable == 1 {
        let _ = api::command(&format!("edit {}", expanded_file));
    } else {
        let _ = api::err_writeln("Invalid format. Expected: file:line:col or file:function_name");
    }
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

            // Call show_markdown_popup from utils
            utils::show_markdown_popup(as_rust_block.to_string());
        }
        _ => {
            let _ = api::err_writeln("Failed to run prettify_log");
        }
    }
}

#[nvim_oxi::plugin]
fn rust_plugins() -> nvim_oxi::Result<Dictionary> {
    let find_todo = Function::from_fn(|()| find_todo_impl());
    let should_rebuild_fn = Function::from_fn(|()| should_rebuild());
    let rebuild_if_needed_fn = Function::from_fn(|()| rebuild_if_needed());
    let parse_log_line_fn = Function::from_fn(|(line,)| parse_log_line(line));
    let popup_log_contents_fn: Function<(String,), ()> = Function::from_fn(|(contents,)| popup_log_contents(contents));
    let smart_keymap_fn: Function<(Object, nvim_oxi::String, Object, Object), ()> =
        Function::from_fn(|(mode, lhs, rhs, opts)| shorthands::smart_keymap(mode, lhs, rhs, opts));

    // Comment functions
    let cs_fn = Function::from_fn(|()| shorthands::infer_comment_string());
    let infer_comment_string_fn = Function::from_fn(|()| shorthands::infer_comment_string());
    let foldmarker_comment_block_fn = Function::from_fn(|(n,)| comment::foldmarker_comment_block(n));
    let remove_eol_comment_fn = Function::from_fn(|()| comment::remove_end_of_line_comment());
    let debug_comment_fn = Function::from_fn(|(action,): (String,)| comment::debug_comment(&action));
    let add_todo_comment_fn = Function::from_fn(|(n,)| comment::add_todo_comment(n));
    let toggle_comments_fn = Function::from_fn(|()| comment::toggle_comments_visibility());
    let goto_file_line_column_or_function_fn = Function::from_fn(|(arg,): (String,)| goto_file_line_column_or_function(arg));

    // Shorthands functions
    let f_fn = Function::from_fn(|(s, mode): (String, Option<String>)| shorthands::f(s, mode));
    let ft_fn = Function::from_fn(|(s, mode): (String, Option<String>)| shorthands::ft(s, mode));

    // Remap functions
    let get_popups_fn = Function::from_fn(|()| remap::get_popups());
    let kill_popups_fn = Function::from_fn(|()| remap::kill_popups());
    let save_session_if_open_fn = Function::from_fn(|(cmd, hook_before): (String, Option<String>)| {
        remap::save_session_if_open(cmd, hook_before)
    });

    // Comment extra
    let comment_extra_reimplementation_fn = Function::from_fn(|(insert_leader,): (String,)| {
        comment::comment_extra_reimplementation(insert_leader)
    });

    // LSP functions
    let echo_fn = Function::from_fn(|(text, hl_type): (String, Option<String>)| {
        lsp::echo(text, hl_type)
    });
    let jump_to_diagnostic_fn = Function::from_fn(|(direction, request_severity): (i64, String)| {
        lsp::jump_to_diagnostic(direction, request_severity)
    });
    let yank_diagnostic_popup_fn = Function::from_fn(|()| lsp::yank_diagnostic_popup());
    let show_markdown_popup_fn = Function::from_fn(|(text,): (String,)| utils::show_markdown_popup(text));

    Ok(Dictionary::from_iter([
        ("find_todo", Object::from(find_todo)),
        ("should_rebuild", Object::from(should_rebuild_fn)),
        ("rebuild_if_needed", Object::from(rebuild_if_needed_fn)),
        ("parse_log_line", Object::from(parse_log_line_fn)),
        ("popup_log_contents", Object::from(popup_log_contents_fn)),
        ("smart_keymap", Object::from(smart_keymap_fn)),
        ("cs", Object::from(cs_fn)),
        ("infer_comment_string", Object::from(infer_comment_string_fn)),
        ("foldmarker_comment_block", Object::from(foldmarker_comment_block_fn)),
        ("remove_end_of_line_comment", Object::from(remove_eol_comment_fn)),
        ("debug_comment", Object::from(debug_comment_fn)),
        ("add_todo_comment", Object::from(add_todo_comment_fn)),
        ("toggle_comments_visibility", Object::from(toggle_comments_fn)),
        ("goto_file_line_column_or_function", Object::from(goto_file_line_column_or_function_fn)),
        ("f", Object::from(f_fn)),
        ("ft", Object::from(ft_fn)),
        ("get_popups", Object::from(get_popups_fn)),
        ("kill_popups", Object::from(kill_popups_fn)),
        ("save_session_if_open", Object::from(save_session_if_open_fn)),
        ("comment_extra_reimplementation", Object::from(comment_extra_reimplementation_fn)),
        ("echo", Object::from(echo_fn)),
        ("jump_to_diagnostic", Object::from(jump_to_diagnostic_fn)),
        ("yank_diagnostic_popup", Object::from(yank_diagnostic_popup_fn)),
        ("show_markdown_popup", Object::from(show_markdown_popup_fn)),
    ]))
}
