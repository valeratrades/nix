use nvim_oxi::api;

/// Get all popup windows in the current tabpage
/// Returns array of window handles that have a zindex (floating windows)
pub fn get_popups() -> Vec<i64> {
    let wins: Vec<i64> = api::call_function("nvim_tabpage_list_wins", (0,))
        .unwrap_or_else(|_| vec![]);

    wins.into_iter()
        .filter(|&win| {
            let config: Result<nvim_oxi::Dictionary, _> =
                api::call_function("nvim_win_get_config", (win,));

            if let Ok(cfg) = config {
                cfg.get("zindex").is_some()
            } else {
                false
            }
        })
        .collect()
}

/// Close all popup windows
pub fn kill_popups() {
    for win in get_popups() {
        let _ = api::call_function::<_, ()>("nvim_win_close", (win, false));
    }
}

/// Save session if open, then execute command
/// If hook_before is provided, execute it before the command
pub fn save_session_if_open(cmd: String, hook_before: Option<String>) {
    // Save session if persisting is enabled
    let persisting: bool = api::call_function("nvim_get_var", ("persisting",))
        .unwrap_or(false);

    if persisting {
        let _ = api::command("SessionSave");
    }

    // Check current mode
    let mode: nvim_oxi::Dictionary = api::call_function("nvim_get_mode", ((),))
        .unwrap_or_else(|_| nvim_oxi::Dictionary::new());

    let mode_str = mode.get("mode")
        .and_then(|o| {
            let s: Result<nvim_oxi::String, _> = o.clone().try_into();
            s.ok()
        })
        .map(|s: nvim_oxi::String| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "n".to_string());

    // If in insert mode, escape and move right
    if mode_str == "i" {
        crate::shorthands::ft("<Esc>l".to_string(), None);
    }

    // Clear search highlighting
    let _ = api::command("noh");

    // Kill popups
    kill_popups();

    // Execute hook_before if provided
    if let Some(hook) = hook_before {
        if !hook.is_empty() {
            let _ = api::command("wa!");
        }
    }

    // Execute the main command
    let _ = api::command(&cmd);
}
