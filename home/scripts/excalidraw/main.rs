#!/home/v/nix/home/scripts/nix-run-cached

---cargo
[package]
edition = "2024"

[dependencies]
clap = { version = "4", features = ["derive"] }
serde_json = "1"
---

use std::{
	fs,
	io::{BufRead, BufReader, Write},
	net::TcpListener,
	path::PathBuf,
	process::{Command, ExitCode},
	sync::{
		Arc,
		atomic::{AtomicU64, Ordering},
	},
	time::{SystemTime, UNIX_EPOCH},
};

use clap::Parser;

const PORT_BASE: u16 = 3741;
const PORT_RETRIES: u16 = 64;
const HEARTBEAT_TIMEOUT_MS: u64 = 8000;
const ASSETS_DIR: &str = "/home/v/nix/home/scripts/excalidraw";

#[derive(Parser)]
#[command(name = "ex", bin_name = "ex", about = "Open an .excalidraw file in the browser editor")]
struct Cli {
	/// Path to the .excalidraw file (extension auto-appended if missing)
	file: PathBuf,

	/// Browser command to use (default: xdg-open)
	#[arg(short, long)]
	browser: Option<String>,

	/// Additional .excalidrawlib library files to pre-load (on top of bundled libraries)
	#[arg(short, long)]
	library: Vec<PathBuf>,

	/// Create the file if it doesn't exist
	#[arg(short, long)]
	touch: bool,

	/// Open in dark mode (default: light)
	#[arg(short, long)]
	dark: bool,
}

fn now_ms() -> u64 {
	SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64
}

fn main() -> ExitCode {
	let mut cli = Cli::parse();

	// Auto-append .excalidraw to the file argument if missing.
	{
		let s = cli.file.to_string_lossy();
		if !s.ends_with(".excalidraw") {
			cli.file = PathBuf::from(format!("{s}.excalidraw"));
		}
	}
	let file_path = &cli.file;

	let name = file_path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_else(|| "excalidraw".to_string());

	let assets = PathBuf::from(ASSETS_DIR);
	let html_path = assets.join("excalidraw-app.html");
	let libs_dir = assets.join("libraries");

	if !file_path.exists() {
		if !cli.touch {
			eprintln!("File not found: {} (use -t to create)", file_path.display());
			return ExitCode::FAILURE;
		}
		if let Some(parent) = file_path.parent() {
			if !parent.as_os_str().is_empty() {
				fs::create_dir_all(parent).unwrap_or_else(|e| {
					eprintln!("Failed to create directory {}: {e}", parent.display());
					std::process::exit(1);
				});
			}
		}
		let empty = r##"{
  "type": "excalidraw",
  "version": 2,
  "source": "ex-new",
  "elements": [],
  "appState": {
    "gridSize": null,
    "gridStep": 5
  },
  "files": {}
}"##;
		fs::write(file_path, empty).unwrap_or_else(|e| {
			eprintln!("Failed to create {}: {e}", file_path.display());
			std::process::exit(1);
		});
		eprintln!("Created: {}", file_path.display());
	}

	let html_template = fs::read_to_string(&html_path).unwrap_or_else(|e| {
		eprintln!("Failed to read {}: {e}", html_path.display());
		std::process::exit(1);
	});
	let (theme, stroke_color, bg_color) = if cli.dark {
		("dark", "#1e1e1e", "#121212")
	} else {
		("light", "#000000", "#ffffff")
	};
	let html = html_template
		.replace("arch -- Excalidraw", &format!("{name} -- Excalidraw"))
		.replace("__THEME__", theme)
		.replace("__STROKE_COLOR__", stroke_color)
		.replace("__VIEW_BG_COLOR__", bg_color);

	// Discover bundled libraries, then append any user-supplied ones.
	let mut all_libs: Vec<PathBuf> = if libs_dir.is_dir() {
		let mut v: Vec<PathBuf> = fs::read_dir(&libs_dir)
			.unwrap_or_else(|e| {
				eprintln!("Failed to read libraries dir {}: {e}", libs_dir.display());
				std::process::exit(1);
			})
			.filter_map(|e| e.ok())
			.map(|e| e.path())
			.filter(|p| p.extension().is_some_and(|x| x == "excalidrawlib"))
			.collect();
		v.sort();
		v
	} else {
		Vec::new()
	};
	all_libs.extend(cli.library.clone());

	// Merge all library files into a single JSON array of .excalidrawlib objects
	let libraries_json = if all_libs.is_empty() {
		"[]".to_string()
	} else {
		let libs: Vec<serde_json::Value> = all_libs.iter().map(|p| {
			let content = fs::read_to_string(p).unwrap_or_else(|e| {
				eprintln!("Failed to read library {}: {e}", p.display());
				std::process::exit(1);
			});
			serde_json::from_str(&content).unwrap_or_else(|e| {
				eprintln!("Failed to parse library {}: {e}", p.display());
				std::process::exit(1);
			})
		}).collect();
		serde_json::to_string(&libs).unwrap()
	};

	let last_heartbeat = Arc::new(AtomicU64::new(now_ms()));

	let (listener, port) = {
		let mut last_err = None;
		let mut found = None;
		for p in PORT_BASE..PORT_BASE + PORT_RETRIES {
			match TcpListener::bind(format!("127.0.0.1:{p}")) {
				Ok(l) => {
					found = Some((l, p));
					break;
				}
				Err(e) => last_err = Some(e),
			}
		}
		found.unwrap_or_else(|| {
			eprintln!("Failed to bind to ports {PORT_BASE}..{}: {}", PORT_BASE + PORT_RETRIES, last_err.unwrap());
			std::process::exit(1);
		})
	};

	eprintln!("Excalidraw ready: http://localhost:{port}");
	eprintln!("Editing: {}", file_path.display());
	eprintln!("Alt+W to save. Ctrl+C to stop.");

	let url = format!("http://localhost:{port}");
	let browser_cmd = cli.browser.clone();
	std::thread::spawn(move || {
		std::thread::sleep(std::time::Duration::from_millis(500));
		let status = match &browser_cmd {
			Some(cmd) => Command::new(cmd).arg(&url).status(),
			None => Command::new("xdg-open").arg(&url).status(),
		};
		if let Err(e) = status {
			eprintln!("Failed to open browser: {e}");
		}
	});

	let hb = Arc::clone(&last_heartbeat);
	std::thread::spawn(move || loop {
		std::thread::sleep(std::time::Duration::from_secs(3));
		if now_ms() - hb.load(Ordering::Relaxed) > HEARTBEAT_TIMEOUT_MS {
			eprintln!("Tab closed, shutting down.");
			std::process::exit(0);
		}
	});

	for stream in listener.incoming() {
		let mut stream = match stream {
			Ok(s) => s,
			Err(_) => continue,
		};

		let mut reader = BufReader::new(stream.try_clone().unwrap());
		let mut request_line = String::new();
		if reader.read_line(&mut request_line).is_err() {
			continue;
		}
		let parts: Vec<&str> = request_line.trim().split(' ').collect();
		if parts.len() < 2 {
			continue;
		}
		let method = parts[0];
		let path = parts[1];

		let mut content_length: usize = 0;
		loop {
			let mut line = String::new();
			if reader.read_line(&mut line).is_err() || line.trim().is_empty() {
				break;
			}
			let lower = line.to_ascii_lowercase();
			if let Some(val) = lower.strip_prefix("content-length:") {
				content_length = val.trim().parse().unwrap_or(0);
			}
		}

		let cors = "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type";

		match (method, path) {
			("OPTIONS", _) => {
				let _ = write!(stream, "HTTP/1.1 204 No Content\r\n{cors}\r\n\r\n");
			}
			("GET", "/") => {
				let len = html.len();
				let _ = write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {len}\r\n{cors}\r\n\r\n{html}");
			}
			("POST", "/api/heartbeat") => {
				last_heartbeat.store(now_ms(), Ordering::Relaxed);
				let _ = write!(stream, "HTTP/1.1 204 No Content\r\n{cors}\r\n\r\n");
			}
			("GET", "/api/libraries") => {
				let len = libraries_json.len();
				let _ = write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len}\r\n{cors}\r\n\r\n{libraries_json}");
			}
			("GET", "/api/load") => match fs::read_to_string(file_path) {
				Ok(content) => {
					let len = content.len();
					let _ = write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len}\r\n{cors}\r\n\r\n{content}");
				}
				Err(e) => {
					let body = format!("{{\"error\":\"{e}\"}}");
					let len = body.len();
					let _ = write!(stream, "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: {len}\r\n{cors}\r\n\r\n{body}");
				}
			},
			("POST", "/api/save") => {
				let mut body = vec![0u8; content_length];
				if std::io::Read::read_exact(&mut reader, &mut body).is_ok() {
					let body_str = String::from_utf8_lossy(&body);
					match serde_json::from_str::<serde_json::Value>(&body_str) {
						Ok(parsed) => {
							let pretty = serde_json::to_string_pretty(&parsed).unwrap();
							if let Err(e) = fs::write(file_path, &pretty) {
								let err_body = format!("{{\"error\":\"{e}\"}}");
								let len = err_body.len();
								let _ = write!(stream, "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: {len}\r\n{cors}\r\n\r\n{err_body}");
							} else {
								let ok = r#"{"ok":true}"#;
								let len = ok.len();
								let _ = write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len}\r\n{cors}\r\n\r\n{ok}");
								eprint!("saved\n");
							}
						}
						Err(e) => {
							let err_body = format!("{{\"error\":\"{e}\"}}");
							let len = err_body.len();
							let _ = write!(stream, "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: {len}\r\n{cors}\r\n\r\n{err_body}");
						}
					}
				}
			}
			_ => {
				let _ = write!(stream, "HTTP/1.1 404 Not Found\r\n{cors}\r\n\r\n");
			}
		}
	}

	ExitCode::SUCCESS
}
