#!/home/v/nix/home/scripts/nix-run-cached

---cargo
[package]
edition = "2024"

[dependencies]
clap = { version = "4", features = ["derive"] }
serde_json = "1"
tokio = { version = "1", features = ["rt", "net", "io-util"] }
tokio-rustls = { version = "0.26", default-features = false, features = ["ring", "tls12"] }
webpki-roots = "1"
---

use std::{
	fs,
	io::{BufRead, BufReader, Write},
	net::TcpListener,
	path::PathBuf,
	process::{Command, ExitCode},
	sync::{
		Arc,
		atomic::{AtomicBool, AtomicU64, Ordering},
	},
	time::{SystemTime, UNIX_EPOCH},
};

use clap::Parser;

const PORT_BASE: u16 = 3741;
const PORT_RETRIES: u16 = 64;
const HEARTBEAT_TIMEOUT_MS: u64 = 8000;
const ASSETS_DIR: &str = "/home/v/nix/home/scripts/excalidraw";
const COLLAB_HOST: &str = "oss-collab.excalidraw.com";
/// collab server only accepts the excalidraw.com origin; the share link points peers there
const COLLAB_ORIGIN: &str = "https://excalidraw.com";

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

	/// Open in light mode (default: dark)
	#[arg(long)]
	light: bool,
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
	// Brush/stroke color is intentionally NOT forced — Excalidraw's own default
	// (first palette slot, white in dark mode) is correct; overriding it only
	// desynced the picker's selected swatch from the active color.
	let theme = if cli.light { "light" } else { "dark" };
	// #ffffff is correct in both themes — Excalidraw's dark theme renders this
	// stored value as the dark canvas, light theme as plain white.
	let html = html_template
		.replace("arch -- Excalidraw", &format!("{name} -- Excalidraw"))
		.replace("__THEME__", theme)
		.replace("__VIEW_BG_COLOR__", "#ffffff")
		.replace("__USERNAME__", &std::env::var("USER").expect("set by login"));

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
	// Watchdog only arms after the first heartbeat — otherwise a slow browser
	// cold-start would race the timeout and kill the server right after the tab opens.
	let heartbeat_armed = Arc::new(AtomicBool::new(false));

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
	eprintln!("Alt+W to save, Alt+R to toggle theme. Ctrl+C to stop.");

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
	let armed = Arc::clone(&heartbeat_armed);
	std::thread::spawn(move || loop {
		std::thread::sleep(std::time::Duration::from_secs(3));
		if armed.load(Ordering::Relaxed) && now_ms() - hb.load(Ordering::Relaxed) > HEARTBEAT_TIMEOUT_MS {
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
		let mut headers: Vec<String> = Vec::new();
		loop {
			let mut line = String::new();
			if reader.read_line(&mut line).is_err() || line.trim().is_empty() {
				break;
			}
			let lower = line.to_ascii_lowercase();
			if let Some(val) = lower.strip_prefix("content-length:") {
				content_length = val.trim().parse().unwrap_or(0);
			}
			headers.push(line.trim_end().to_string());
		}

		let cors = "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type";

		match (method, path) {
			("GET", p) if p.starts_with("/socket.io/") => {
				assert!(reader.buffer().is_empty(), "ws client sends nothing before the 101");
				let path = p.to_string();
				std::thread::spawn(move || {
					if let Err(e) = proxy_collab(stream, &path, &headers) {
						eprintln!("collab proxy: {e}");
					}
				});
			}
			("OPTIONS", _) => {
				let _ = write!(stream, "HTTP/1.1 204 No Content\r\n{cors}\r\n\r\n");
			}
			("GET", "/") => {
				let len = html.len();
				let _ = write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {len}\r\n{cors}\r\n\r\n{html}");
			}
			("POST", "/api/heartbeat") => {
				last_heartbeat.store(now_ms(), Ordering::Relaxed);
				heartbeat_armed.store(true, Ordering::Relaxed);
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

/// Byte-level passthrough of the browser's websocket upgrade to the excalidraw collab server, with Host/Origin rewritten.
fn proxy_collab(client: std::net::TcpStream, path: &str, headers: &[String]) -> std::io::Result<()> {
	use tokio::io::AsyncWriteExt;
	let mut req = format!("GET {path} HTTP/1.1\r\nHost: {COLLAB_HOST}\r\nOrigin: {COLLAB_ORIGIN}\r\n");
	for h in headers {
		let name = h.split(':').next().unwrap().trim().to_ascii_lowercase();
		if name != "host" && name != "origin" {
			req.push_str(h);
			req.push_str("\r\n");
		}
	}
	req.push_str("\r\n");

	client.set_nonblocking(true)?;
	tokio::runtime::Builder::new_current_thread().enable_io().build()?.block_on(async {
		let mut client = tokio::net::TcpStream::from_std(client)?;
		let roots = tokio_rustls::rustls::RootCertStore { roots: webpki_roots::TLS_SERVER_ROOTS.to_vec() };
		let config = tokio_rustls::rustls::ClientConfig::builder_with_provider(tokio_rustls::rustls::crypto::ring::default_provider().into())
			.with_safe_default_protocol_versions()
			.unwrap()
			.with_root_certificates(roots)
			.with_no_client_auth();
		let tcp = tokio::net::TcpStream::connect((COLLAB_HOST, 443)).await?;
		let mut upstream = tokio_rustls::TlsConnector::from(Arc::new(config)).connect(COLLAB_HOST.try_into().unwrap(), tcp).await?;
		upstream.write_all(req.as_bytes()).await?;
		tokio::io::copy_bidirectional(&mut client, &mut upstream).await.map(|_| ())
	})
}
