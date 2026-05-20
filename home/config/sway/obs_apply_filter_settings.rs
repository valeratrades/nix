#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
sha2 = "0.10"
base64 = "0.22"
---

use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use clap::Parser;
use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::PathBuf;
use std::process::{Command, exit};

/// Apply declarative filter settings to OBS via obs-websocket.
#[derive(Parser, Debug)]
#[command(name = "obs-apply-filter-settings")]
#[command(about = "Push filter settings from a Nix config file to OBS")]
struct Args {
    /// Path to the filter settings .nix file
    #[arg(default_value = "")]
    settings_file: String,

    /// Don't wait; fail immediately if OBS isn't reachable
    #[arg(short, long)]
    no_wait: bool,
}

#[derive(Deserialize)]
struct FilterSpec {
    filters: Vec<FilterEntry>,
}

#[derive(Deserialize)]
struct FilterEntry {
    source: String,
    filter: String,
    settings: Value,
}

#[derive(Deserialize)]
struct ObsWebsocketConfig {
    server_port: u16,
    server_password: String,
}

#[derive(Deserialize)]
struct HelloAuth {
    challenge: String,
    salt: String,
}

#[derive(Deserialize)]
struct HelloMsg {
    d: HelloD,
}

#[derive(Deserialize)]
struct HelloD {
    authentication: Option<HelloAuth>,
}

/// Read exactly one WebSocket frame as a UTF-8 string.
fn ws_read(stream: &mut TcpStream) -> Result<String, String> {
    // Read first 2 bytes to get opcode and length
    let mut header = [0u8; 2];
    stream
        .read_exact(&mut header)
        .map_err(|e| format!("read ws header: {e}"))?;

    let opcode = header[0] & 0x0F;
    if opcode == 0x8 {
        return Err("server closed connection".into());
    }
    if opcode != 0x1 {
        return Err(format!("unexpected opcode {opcode}, wanted text(1)"));
    }

    let mut len = (header[1] & 0x7F) as u64;
    let masked = (header[1] & 0x80) != 0;

    if len == 126 {
        let mut ext = [0u8; 2];
        stream.read_exact(&mut ext).map_err(|e| format!("read ext2: {e}"))?;
        len = u16::from_be_bytes(ext) as u64;
    } else if len == 127 {
        let mut ext = [0u8; 8];
        stream.read_exact(&mut ext).map_err(|e| format!("read ext8: {e}"))?;
        len = u64::from_be_bytes(ext);
    }

    let mut mask_key = [0u8; 4];
    if masked {
        stream.read_exact(&mut mask_key).map_err(|e| format!("read mask: {e}"))?;
    }

    let mut payload = vec![0u8; len as usize];
    stream.read_exact(&mut payload).map_err(|e| format!("read payload ({len} bytes): {e}"))?;

    if masked {
        for (i, b) in payload.iter_mut().enumerate() {
            *b ^= mask_key[i % 4];
        }
    }

    String::from_utf8(payload).map_err(|e| format!("utf8: {e}"))
}

/// Send a WebSocket text frame.
fn ws_write(stream: &mut TcpStream, text: &str) -> Result<(), String> {
    let payload = text.as_bytes();
    let len = payload.len();

    // Build frame
    let mut frame = Vec::with_capacity(len + 14);
    frame.push(0x81); // FIN + text opcode

    if len < 126 {
        frame.push(len as u8 | 0x80); // masked (client → server must mask)
    } else if len <= u16::MAX as usize {
        frame.push(126 | 0x80);
        frame.extend_from_slice(&(len as u16).to_be_bytes());
    } else {
        frame.push(127 | 0x80);
        frame.extend_from_slice(&(len as u64).to_be_bytes());
    }

    // Mask key (random-ish)
    let mask: [u8; 4] = [0x12, 0x34, 0x56, 0x78];
    frame.extend_from_slice(&mask);
    frame.extend(payload.iter().enumerate().map(|(i, b)| b ^ mask[i % 4]));

    stream
        .write_all(&frame)
        .map_err(|e| format!("write: {e}"))
}

fn main() {
    let args = Args::parse();

    let settings_file = if args.settings_file.is_empty() {
        let home = std::env::var("HOME").expect("HOME");
        format!("{home}/.config/obs-studio/filter_settings.nix")
    } else {
        args.settings_file
    };

    // Evaluate the Nix config file to JSON
    let eval = Command::new("nix")
        .args(["eval", "--json", "--file", &settings_file])
        .output()
        .expect("failed to run nix eval");

    if !eval.status.success() {
        let stderr = String::from_utf8_lossy(&eval.stderr);
        eprintln!("nix eval failed: {stderr}");
        exit(1);
    }

    let spec: FilterSpec =
        serde_json::from_slice(&eval.stdout).expect("invalid filter settings");

    // Read obs-websocket config
    let obs_cfg_path = PathBuf::from(
        std::env::var("HOME").expect("HOME"),
    )
    .join(".config/obs-studio/plugin_config/obs-websocket/config.json");

    let max_attempts = if args.no_wait { 1 } else { 5 };
    let cfg: ObsWebsocketConfig = loop {
        match std::fs::read_to_string(&obs_cfg_path) {
            Ok(s) => match serde_json::from_str(&s) {
                Ok(c) => break c,
                Err(e) => {
                    eprintln!("obs-websocket config parse error: {e}");
                    if max_attempts == 1 {
                        exit(1);
                    }
                }
            },
            Err(_) => {
                if max_attempts == 1 {
                    eprintln!("obs-websocket config not found at {}", obs_cfg_path.display());
                    exit(1);
                }
            }
        }
        eprintln!("Waiting for obs-websocket config...");
        std::thread::sleep(std::time::Duration::from_secs(1));
    };

    // Connect
    let mut stream = (|| {
        for attempt in 0..max_attempts {
            match TcpStream::connect(format!("127.0.0.1:{}", cfg.server_port)) {
                Ok(s) => return Ok(s),
                Err(e) => {
                    if attempt + 1 < max_attempts {
                        eprintln!("Waiting for obs-websocket ({e})...");
                        std::thread::sleep(std::time::Duration::from_secs(1));
                    } else {
                        return Err(e);
                    }
                }
            }
        }
        unreachable!()
    })()
    .unwrap_or_else(|e| {
        eprintln!("Could not connect to obs-websocket after {max_attempts} attempts: {e}");
        exit(1);
    });

    stream
        .set_read_timeout(Some(std::time::Duration::from_secs(3)))
        .expect("set read timeout");

    // WebSocket upgrade
    let host = format!("localhost:{}", cfg.server_port);
    let key: String = B64.encode(&[0u8; 16]);
    let upgrade_req = format!(
        "GET / HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
    );
    stream.write_all(upgrade_req.as_bytes()).expect("ws upgrade write");

    // Read HTTP response byte-by-byte until \r\n\r\n (no buffering, to avoid
    // consuming WebSocket frames into a BufReader buffer).
    let mut buf = Vec::new();
    let mut prev = [0u8; 4];
    loop {
        let mut b = [0u8; 1];
        stream.read_exact(&mut b).expect("read http status line");
        buf.push(b[0]);
        prev.copy_within(1.., 0);
        prev[3] = b[0];
        if &prev == b"\r\n\r\n" {
            break;
        }
    }
    let response = String::from_utf8_lossy(&buf);
    if !response.contains("101") {
        eprintln!("WebSocket upgrade failed:\n{response}");
        exit(1);
    }

    // --- obs-websocket v5 auth handshake ---
    // 1. Read Hello
    let hello_raw = ws_read(&mut stream).expect("read hello");
    let hello: HelloMsg = serde_json::from_str(&hello_raw).expect("parse hello");
    let auth = hello.d.authentication.expect("no auth in hello");

    // 2. Compute auth response
    let secret = B64.encode(Sha256::digest(format!("{}{}", cfg.server_password, auth.salt)));
    let auth_response = B64.encode(Sha256::digest(format!("{secret}{}", auth.challenge)));

    // 3. Send Identify
    let identify = serde_json::json!({
        "op": 1,
        "d": {
            "rpcVersion": 1,
            "authentication": auth_response,
            "eventSubscriptions": 0,
        },
    });
    ws_write(&mut stream, &identify.to_string()).expect("send identify");
    let identified_raw = ws_read(&mut stream).expect("read identified");
    let identified: Value = serde_json::from_str(&identified_raw).expect("parse identified");
    if identified["op"] != 2 {
        eprintln!("Identify failed: {identified_raw}");
        exit(1);
    }

    // 4. Send SetSourceFilterSettings for each entry
    let mut request_id = 0u64;
    for entry in &spec.filters {
        request_id += 1;
        let req = serde_json::json!({
            "op": 6,
            "d": {
                "requestType": "SetSourceFilterSettings",
                "requestId": request_id.to_string(),
                "requestData": {
                    "sourceName": entry.source,
                    "filterName": entry.filter,
                    "filterSettings": entry.settings,
                    "overlay": false,
                },
            },
        });
        ws_write(&mut stream, &req.to_string())
            .unwrap_or_else(|e| {
                eprintln!("Failed to send settings for '{}' on '{}': {e}", entry.filter, entry.source);
            });

        match ws_read(&mut stream) {
            Ok(resp) => {
                let v: Value = serde_json::from_str(&resp).unwrap_or_default();
                if v["op"] == 7 && v["d"]["requestStatus"]["result"].as_bool() == Some(true) {
                    println!(
                        "Applied {} settings to '{}' on '{}'",
                        entry.settings.as_object().map(|o| o.len()).unwrap_or(0),
                        entry.filter,
                        entry.source,
                    );
                } else {
                    let err = &v["d"]["requestStatus"]["comment"];
                    eprintln!("Failed on '{}'/'{}': {}", entry.source, entry.filter, err);
                }
            }
            Err(e) => {
                eprintln!("No response for '{}'/'{}': {e}", entry.filter, entry.source);
            }
        }
    }

    // Clean close
    let _ = ws_write(&mut stream, &serde_json::json!({"op": 7, "d": {"requestType": "Noop", "requestId": "bye"}}).to_string());
}
