#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
---

use std::collections::HashMap;
use std::env;
use std::process::Command;

fn main() {
    let args: Vec<String> = env::args().collect();
    let debug_category = args.get(1).map(|s| s.as_str());

    let profile_output = Command::new("fish")
        .args(["--profile-startup=/dev/stdout", "-c", "exit"])
        .output()
        .expect("Failed to run fish");

    let output = String::from_utf8_lossy(&profile_output.stdout);

    let mut categories: HashMap<&str, u64> = HashMap::new();
    let mut debug_lines: Vec<(u64, String)> = Vec::new();

    for line in output.lines().skip(1) {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 3 {
            continue;
        }

        let time_us: u64 = match parts[0].parse() {
            Ok(t) => t,
            Err(_) => continue,
        };

        let cmd = parts[2..].join(" ");
        let category = categorize(&cmd);

        if let Some(debug_cat) = debug_category {
            if category == debug_cat && time_us > 100 {
                debug_lines.push((time_us, cmd.chars().take(120).collect()));
            }
        }

        *categories.entry(category).or_insert(0) += time_us;
    }

    // Debug mode: show individual commands in category
    if let Some(debug_cat) = debug_category {
        debug_lines.sort_by(|a, b| b.0.cmp(&a.0));
        println!("Debug: Top commands in '{}' category", debug_cat);
        println!("══════════════════════════════════════════════════════════════════");
        for (time_us, cmd) in debug_lines.iter().take(30) {
            println!("{:>8.1}ms  {}", *time_us as f64 / 1000.0, cmd);
        }
        return;
    }

    let mut sorted: Vec<_> = categories.into_iter().collect();
    sorted.sort_by(|a, b| b.1.cmp(&a.1));

    let total_us: u64 = sorted.iter().map(|(_, t)| *t).sum();
    let max_time = sorted.first().map(|(_, t)| *t).unwrap_or(1);

    println!("Fish Shell Startup Profile");
    println!("══════════════════════════════════════════════════════════════════");
    println!();
    println!("{:<35} {:>10}    Bar", "Component", "Time (ms)");
    println!("──────────────────────────────────────────────────────────────────");

    for (category, time_us) in &sorted {
        if *time_us < 100 {
            continue; // Skip entries under 0.1ms
        }

        let time_ms = *time_us as f64 / 1000.0;
        let bar_len = (*time_us as f64 / max_time as f64 * 40.0) as usize;
        let bar: String = "█".repeat(bar_len.max(1).min(40));

        println!("{:<35} {:>10.1}    {}", category, time_ms, bar);
    }

    println!("──────────────────────────────────────────────────────────────────");
    println!("{:<35} {:>10.1} ms", "TOTAL", total_us as f64 / 1000.0);
    println!();
    println!("Tip: Run with category name to debug, e.g.: profile_shell_init.rs other");
}

fn categorize(cmd: &str) -> &'static str {
    // Cached init sources
    if cmd.contains("source") && cmd.contains("shell_init") {
        if cmd.contains("zoxide") {
            return "zoxide init (cached)";
        } else if cmd.contains("todo") {
            return "todo init (cached)";
        } else if cmd.contains("tg") {
            return "tg init (cached)";
        } else if cmd.contains("himalaya") {
            return "himalaya (cached)";
        } else if cmd.contains("atuin") {
            return "atuin init (cached)";
        } else if cmd.contains("starship") {
            return "starship init (cached)";
        } else if cmd.contains("watchexec") {
            return "watchexec (cached)";
        } else if cmd.contains("shuttle") {
            return "shuttle (cached)";
        } else if cmd.contains("discretionary") {
            return "discretionary_engine (cached)";
        }
    }

    // Config file sources
    if cmd.contains("source") && cmd.contains("credentials") {
        "credentials.fish"
    } else if cmd.contains("source") && cmd.contains("global.fish") {
        "global.fish"
    } else if cmd.contains("source") && cmd.contains("other.fish") {
        "other.fish"
    } else if cmd.contains("source") && cmd.contains("cli_translate") {
        "cli_translate.fish"
    } else if cmd.contains("source") && cmd.contains("cs_nav") {
        "cs_nav.fish"
    } else if cmd.contains("source") && cmd.contains("app_aliases") {
        "app_aliases"
    } else if cmd.contains("source") && cmd.contains("eww") {
        "eww config"
    } else if cmd.contains("source") && cmd.contains("tmux") {
        "tmux config"
    } else if cmd.contains("source") && cmd.contains("file_snippets") {
        "file_snippets"
    } else if cmd.contains("source") && cmd.contains("scripts/__main__") {
        "scripts/__main__.fish"
    // Non-cached init commands (fallback if cache miss)
    } else if cmd.contains("todo init") {
        "todo init"
    } else if cmd.contains("tg init") {
        "tg init"
    } else if cmd.contains("himalaya") {
        "himalaya completion"
    } else if cmd.contains("watchexec") {
        "watchexec completion"
    } else if cmd.contains("shuttle") {
        "shuttle"
    } else if cmd.contains("discretionary_engine") {
        "discretionary_engine init"
    } else if cmd.contains("atuin") {
        "atuin init"
    } else if cmd.contains("starship") {
        "starship init"
    } else if cmd.contains("zoxide") {
        "zoxide init"
    // Utility commands
    } else if cmd.contains("check_nightly_versions") {
        "check_nightly_versions"
    } else if cmd.contains("fd ") || cmd.contains("fd -") {
        "fd (file discovery)"
    } else if cmd.contains("grep") {
        "grep"
    } else if cmd.contains("fenv") {
        "fenv (foreign-env)"
    } else if cmd.contains("flatpak") {
        "flatpak"
    } else if cmd.contains("cached_init") {
        "cached_init overhead"
    } else if cmd.contains("complete ") {
        "completions"
    } else if cmd.contains("function ") {
        "function definitions"
    } else if cmd.contains("alias ") {
        "aliases"
    } else if cmd.contains("set ") || cmd.contains("set -") {
        "variable assignments"
    } else if cmd.contains("bind ") {
        "key bindings"
    } else if cmd.contains("command -v") || cmd.contains("command -q") {
        "command checks"
    } else if cmd.contains("test ") || cmd.contains("test -") {
        "test conditions"
    } else if cmd.contains("string ") {
        "string operations"
    } else if cmd.contains("bash") {
        "bash invocations"
    } else if cmd.contains("__fish") {
        "fish internals"
    } else if cmd.contains("source") && cmd.contains("cache_file") {
        "cached_init source"
    } else if cmd.contains("direnv") {
        "direnv hook"
    } else if cmd.contains("dirname") {
        "dirname calls"
    } else if cmd.contains("rg ") || cmd.contains("command rg") {
        "ripgrep"
    } else if cmd.contains("sed ") {
        "sed"
    } else if cmd.contains("tty") {
        "tty check"
    } else if cmd.contains("cat ") {
        "cat"
    } else if cmd.contains("date ") {
        "date"
    } else if cmd.contains("mkdir") {
        "mkdir"
    } else if cmd.contains("for ") && cmd.contains("in ") {
        "for loops"
    } else if cmd.contains("source") {
        "other source"
    } else if cmd.contains("eval ") {
        "eval"
    } else if cmd.contains("read ") {
        "read"
    } else if cmd.contains("printf") || cmd.contains("echo") {
        "output"
    } else if cmd.contains("math ") {
        "math"
    } else if cmd.contains("count ") {
        "count"
    } else if cmd.contains("status ") {
        "status checks"
    } else if cmd.contains("contains ") {
        "contains checks"
    } else if cmd.contains("argparse") {
        "argparse"
    } else {
        "other"
    }
}
