use nvim_oxi::{api, Array, Dictionary, Function, Object};
use std::process::Command;

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
        let parts: Vec<&str> = line.splitn(5, ':').collect();
        if parts.len() >= 5 {
            // parts[0] = count of '!' from awk (not used in quickfix)
            // parts[1] = filename
            // parts[2] = line number
            // parts[3] = column (from rg)
            // parts[4] = content

            let filename = parts[1].to_string();
            let lnum = parts[2].parse::<i64>().unwrap_or(0);
            let text = parts[4].to_string();

            let entry = Dictionary::from_iter([
                ("filename", Object::from(filename)),
                ("lnum", Object::from(lnum)),
                ("text", Object::from(text)),
            ]);

            qf_entries.push(Object::from(entry));
        }
    }

    // Set the quickfix list using vim.fn.setqflist
    let qf_array = Array::from_iter(qf_entries);
    if let Err(e) = api::call_function::<_, ()>("setqflist", (qf_array, "r")) {
        let _ = api::err_writeln(&format!("Error setting quickfix list: {}", e));
        return;
    }

    // Set mark 'T' to allow jumping back
    if let Err(e) = api::command("mark T") {
        let _ = api::err_writeln(&format!("Error setting mark: {}", e));
    }
}

#[nvim_oxi::plugin]
fn rust_plugins() -> nvim_oxi::Result<Dictionary> {
    let find_todo = Function::from_fn(|()| find_todo_impl());

    Ok(Dictionary::from_iter([("find_todo", Object::from(find_todo))]))
}
