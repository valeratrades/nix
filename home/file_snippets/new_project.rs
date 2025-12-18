#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
cmd_lib = "1"
chrono = "0.4"
---

use chrono::{Duration, Utc};
use clap::{Parser, Subcommand, ValueEnum};
use cmd_lib::{run_cmd, run_fun};
use std::{env, fs, path::PathBuf, process::Command};

#[derive(Parser)]
#[command(name = "new_project")]
#[command(about = "Create new projects with standard scaffolding")]
struct Args {
    #[command(subcommand)]
    command: ProjectCommand,
}

#[derive(Subcommand)]
enum ProjectCommand {
    /// Create a new Rust/Cargo project
    Rust {
        /// Project name
        name: String,

        /// Toolchain to use
        #[arg(long, default_value = "stable")]
        toolchain: Toolchain,

        /// Project preset
        #[arg(long, default_value = "default")]
        preset: RustPreset,
    },
    /// Create a new Python project
    Python {
        /// Project name
        name: String,
    },
    /// Create a new Go project
    Golang {
        /// Project name
        name: String,
    },
    /// Create a new Lean project
    Lean {
        /// Project name
        name: String,
    },
    /// Create a new Typst project
    Typst {
        /// Project name
        name: String,
    },
}

#[derive(Clone, ValueEnum, Default)]
enum Toolchain {
    #[default]
    Stable,
    Nightly,
}

#[derive(Clone, ValueEnum, Default)]
enum RustPreset {
    #[default]
    Default,
    Clap,
    Tokio,
    Leptos,
    Light,
}

fn get_file_snippets_path() -> PathBuf {
    let nixos_config = env::var("NIXOS_CONFIG").unwrap_or_else(|_| {
        eprintln!("ERROR: NIXOS_CONFIG is not set");
        std::process::exit(1);
    });
    PathBuf::from(nixos_config).join("home/file_snippets")
}

fn get_github_user() -> String {
    env::var("GITHUB_USER").unwrap_or_else(|_| {
        eprintln!("ERROR: GITHUB_USER is not set");
        std::process::exit(1);
    })
}

fn get_github_name() -> String {
    env::var("GITHUB_NAME").unwrap_or_else(|_| {
        eprintln!("ERROR: GITHUB_NAME is not set");
        std::process::exit(1);
    })
}

fn get_rustc_version() -> String {
    run_fun!(rustc -V | sed -E "s/rustc ([0-9]+\\.[0-9]+).*/\\1/")
        .unwrap_or_else(|_| "1.75".to_string())
}

fn get_nightly_date() -> String {
    let yesterday = Utc::now() - Duration::days(1);
    format!("nightly-{}", yesterday.format("%Y-%m-%d"))
}

fn get_nixpkgs_version() -> String {
    Command::new("sh")
        .args([
            "-c",
            r#"git ls-remote --heads https://github.com/NixOS/nixpkgs | grep -o 'refs/heads/nixos-[0-9][0-9]\.[0-9][0-9]' | cut -d'/' -f3 | tail -n 1"#,
        ])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "nixos-24.05".to_string())
}

fn get_python_version() -> String {
    run_fun!(python -V | cut -d " " -f2).unwrap_or_else(|_| "3.11".to_string())
}

fn replace_placeholders(dir: &PathBuf, project_name: &str) {
    let rustc_version = get_rustc_version();
    let nightly_date = get_nightly_date();
    let nixpkgs_version = get_nixpkgs_version();
    let python_version = get_python_version();
    let github_user = get_github_user();

    let output = Command::new("fd")
        .args([
            "--type",
            "f",
            "--exclude",
            ".git",
            "--exclude",
            ".gitignore",
        ])
        .current_dir(dir)
        .output()
        .expect("Failed to run fd");

    let files = String::from_utf8_lossy(&output.stdout);
    for file in files.lines() {
        if file.is_empty() {
            continue;
        }
        let file_path = dir.join(file);
        if let Ok(content) = fs::read_to_string(&file_path) {
            let new_content = content
                .replace("PROJECT_NAME_PLACEHOLDER", project_name)
                .replace("RUSTC_CURRENT_VERSION", &rustc_version)
                .replace("CURRENT_NIGHTLY_BY_DATE", &nightly_date)
                .replace("NIXPKGS_VERSION", &nixpkgs_version)
                .replace("PYTHON_VERSION", &python_version)
                .replace("GITHUB_USER", &github_user);

            if new_content != content {
                fs::write(&file_path, new_content).ok();
            }
        }
    }
}

fn shared_before(project_name: &str, lang: &str) -> Result<(), Box<dyn std::error::Error>> {
    let file_snippets = get_file_snippets_path();

    env::set_current_dir(project_name)?;

    // Create docs directory with ARCHITECTURE.md
    fs::create_dir_all("docs/.assets")?;
    let arch_src = file_snippets.join("docs/ARCHITECTURE.md");
    if arch_src.exists() {
        fs::copy(&arch_src, "docs/ARCHITECTURE.md")?;
    }

    // Create tests directory
    fs::create_dir_all("tests")?;
    let tests_src = file_snippets.join(format!("tests/{}", lang));
    if tests_src.exists() {
        let entries: Vec<_> = fs::read_dir(&tests_src)?.filter_map(|e| e.ok()).collect();
        if !entries.is_empty() {
            for entry in entries {
                let dest = PathBuf::from("tests").join(entry.file_name());
                if entry.path().is_dir() {
                    copy_dir_all(&entry.path(), &dest)?;
                } else {
                    fs::copy(entry.path(), dest)?;
                }
            }
        } else {
            println!(
                "skipping tests initialization, as no tests discovered in {:?}",
                tests_src
            );
        }
    } else {
        println!(
            "skipping tests initialization, as no tests directory found for {}",
            lang
        );
    }

    // Create tmp directory
    fs::create_dir_all("tmp")?;

    // Copy flake.nix if it exists for this language
    let flake_src = file_snippets.join(format!("{}/flake.nix", lang));
    if flake_src.exists() {
        fs::copy(&flake_src, "flake.nix")?;
    }

    // Create .envrc
    let envrc_content = if lang == "py" {
        "use flake . --no-pure-eval\n"
    } else {
        "use flake\n"
    };
    fs::write(".envrc", envrc_content)?;

    Ok(())
}

fn shared_after(project_name: &str, _lang: &str) -> Result<(), Box<dyn std::error::Error>> {
    run_cmd!(git init)?;

    let current_dir = env::current_dir()?;
    replace_placeholders(&current_dir, project_name);

    run_cmd!(git add -A)?;
    run_cmd!(git commit -m "-- New Project Snippet --")?;
    run_cmd!(git branch release)?;

    Ok(())
}

fn copy_dir_all(src: &PathBuf, dst: &PathBuf) -> Result<(), Box<dyn std::error::Error>> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        if ty.is_dir() {
            copy_dir_all(&entry.path(), &dst.join(entry.file_name()))?;
        } else {
            fs::copy(entry.path(), dst.join(entry.file_name()))?;
        }
    }
    Ok(())
}

fn rust(
    name: &str,
    _toolchain: &Toolchain,
    preset: &RustPreset,
) -> Result<(), Box<dyn std::error::Error>> {
    let file_snippets = get_file_snippets_path();
    let lang = "rs";

    // cargo new
    run_cmd!(cargo new $name)?;
    shared_before(name, lang)?;

    // Create rust-toolchain.toml for nightly with cranelift
    fs::create_dir_all(".cargo")?;
    fs::write(
        ".cargo/rust-toolchain.toml",
        r#"
[toolchain]
channel = "nightly"
components = ["rustc-codegen-cranelift-preview"]"#,
    )?;

    // Modify Cargo.toml
    let cargo_toml = fs::read_to_string("Cargo.toml")?;
    let mut lines: Vec<&str> = cargo_toml.lines().collect();
    if !lines.is_empty() {
        lines.pop(); // Remove last line
    }
    let mut new_content = String::from("cargo-features = [\"codegen-backend\"]\n");
    new_content.push_str(&lines.join("\n"));
    new_content.push('\n');

    // Append default dependencies
    let default_deps = file_snippets.join(format!("{}/default_dependencies.toml", lang));
    if default_deps.exists() {
        new_content.push_str(&fs::read_to_string(&default_deps)?);
    }
    fs::write("Cargo.toml", &new_content)?;

    // Remove default src directory
    let _ = fs::remove_dir_all("src");

    // Copy preset files
    let preset_name = match preset {
        RustPreset::Clap => "clap",
        RustPreset::Tokio => "tokio",
        RustPreset::Leptos => "leptos",
        RustPreset::Light => "light",
        RustPreset::Default => "default",
    };

    let preset_dir = file_snippets.join(format!("{}/presets/{}", lang, preset_name));

    match preset {
        RustPreset::Leptos => {
            // Copy entire preset directory contents
            if preset_dir.exists() {
                for entry in fs::read_dir(&preset_dir)? {
                    let entry = entry?;
                    let dest = PathBuf::from(".").join(entry.file_name());
                    if entry.path().is_dir() {
                        copy_dir_all(&entry.path(), &dest)?;
                    } else {
                        fs::copy(entry.path(), &dest)?;
                    }
                }
            }
            // Append additional dependencies if present
            let additional = PathBuf::from("additional_dependencies.toml");
            if additional.exists() {
                let cargo = fs::read_to_string("Cargo.toml")?;
                let additional_content = fs::read_to_string(&additional)?;
                fs::write("Cargo.toml", format!("{}{}", cargo, additional_content))?;
                let _ = fs::remove_file(&additional);
            }
        }
        RustPreset::Default => {
            // Copy src directory
            let src_dir = preset_dir.join("src");
            if src_dir.exists() {
                copy_dir_all(&src_dir, &PathBuf::from("src"))?;
            }
            // Copy build.rs
            let build_rs = preset_dir.join("build.rs");
            if build_rs.exists() {
                fs::copy(&build_rs, "build.rs")?;
            }
            // Append additional dependencies
            let additional = preset_dir.join("additional_dependencies.toml");
            if additional.exists() {
                let cargo = fs::read_to_string("Cargo.toml")?;
                fs::write(
                    "Cargo.toml",
                    format!("{cargo}{}", fs::read_to_string(&additional)?),
                )?;
            }
        }
        _ => {
            // Copy src directory
            let src_dir = preset_dir.join("src");
            if src_dir.exists() {
                copy_dir_all(&src_dir, &PathBuf::from("src"))?;
            }
            // Append additional dependencies
            let additional = preset_dir.join("additional_dependencies.toml");
            if additional.exists() {
                let cargo = fs::read_to_string("Cargo.toml")?;
                fs::write(
                    "Cargo.toml",
                    format!("{cargo}{}", fs::read_to_string(&additional)?),
                )?;
            }
        }
    }

    // Create lib.rs
    fs::write("src/lib.rs", "")?;

    shared_after(name, lang)?;

    Ok(())
}

fn python(name: &str) -> Result<(), Box<dyn std::error::Error>> {
    let file_snippets = get_file_snippets_path();
    let lang = "py";

    fs::create_dir_all(name)?;
    shared_before(name, lang)?;

    // Copy preset files
    let preset_dir = file_snippets.join(format!("{}/presets/default", lang));
    if preset_dir.exists() {
        for entry in fs::read_dir(&preset_dir)? {
            let entry = entry?;
            let dest = PathBuf::from(".").join(entry.file_name());
            if entry.path().is_dir() {
                copy_dir_all(&entry.path(), &dest)?;
            } else {
                fs::copy(entry.path(), &dest)?;
            }
        }
    }

    // Copy flake.nix and pyproject.toml
    let flake_src = file_snippets.join(format!("{}/flake.nix", lang));
    if flake_src.exists() {
        fs::copy(&flake_src, "flake.nix")?;
    }
    let pyproject_src = file_snippets.join(format!("{}/pyproject.toml", lang));
    if pyproject_src.exists() {
        fs::copy(&pyproject_src, "pyproject.toml")?;
    }

    shared_after(name, lang)?;

    Ok(())
}

fn golang(name: &str) -> Result<(), Box<dyn std::error::Error>> {
    let file_snippets = get_file_snippets_path();
    let lang = "go";
    let github_name = get_github_name();

    fs::create_dir_all(name)?;
    shared_before(name, lang)?;

    // Link gofumpt.toml
    let gofumpt_src = file_snippets.join(format!("{lang}/gofumpt.toml"));
    if gofumpt_src.exists() {
        // Use hard link (sudo required in original, try without first)
        let _ = fs::hard_link(&gofumpt_src, "gofumpt.toml")
            .or_else(|_| fs::copy(&gofumpt_src, "gofumpt.toml").map(|_| ()));
    }

    // Copy preset files (includes cmd/main.go)
    let preset_dir = file_snippets.join(format!("{lang}/presets/default"));
    if preset_dir.exists() {
        for entry in fs::read_dir(&preset_dir)? {
            let entry = entry?;
            let dest = PathBuf::from(".").join(entry.file_name());
            if entry.path().is_dir() {
                copy_dir_all(&entry.path(), &dest)?;
            } else {
                fs::copy(entry.path(), &dest)?;
            }
        }
    }

    shared_after(name, lang)?;

    // Initialize go module
    let module_path = format!("github.com/{github_name}/{name}");
    run_cmd!(go mod init $module_path)?;
    run_cmd!(go mod tidy)?;

    Ok(())
}

fn lean(name: &str) -> Result<(), Box<dyn std::error::Error>> {
    let file_snippets = get_file_snippets_path();

    run_cmd!(elan run --install nightly lake new $name)?;
    shared_before(name, "lean")?;

    // Copy leanpkg.toml
    let leanpkg_src = file_snippets.join("leanpkg.toml");
    if leanpkg_src.exists() {
        fs::copy(&leanpkg_src, "leanpkg.toml")?;
    }

    Ok(())
}

fn typst(name: &str) -> Result<(), Box<dyn std::error::Error>> {
    let file_snippets = get_file_snippets_path();
    let lang = "typ";

    fs::create_dir_all(name)?;
    shared_before(name, lang)?;

    // Create assets directory
    fs::create_dir_all("assets")?;

    // Copy flake.nix
    let flake_src = file_snippets.join(format!("{lang}/flake.nix"));
    if flake_src.exists() {
        fs::copy(&flake_src, "flake.nix")?;
    }

    // Copy __main__.typ
    let main_src = file_snippets.join(format!("{lang}/presets/default/__main__.typ"));
    if main_src.exists() {
        fs::copy(&main_src, "__main__.typ")?;
    }

    shared_after(name, lang)?;

    Ok(())
}

fn main() {
    let args = Args::parse();

    let result = match args.command {
        ProjectCommand::Rust {
            name,
            toolchain,
            preset,
        } => rust(&name, &toolchain, &preset),
        ProjectCommand::Python { name } => python(&name),
        ProjectCommand::Golang { name } => golang(&name),
        ProjectCommand::Lean { name } => lean(&name),
        ProjectCommand::Typst { name } => typst(&name),
    };

    if let Err(e) = result {
        eprintln!("ERROR: {}", e);
        std::process::exit(1);
    }
}
