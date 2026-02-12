#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
---

use clap::Parser;
use std::process::Command;

/// Send a keypress to a sway window by app_id, without disrupting current focus.
///
/// Sway/Wayland has no way to send input to an unfocused window.
/// This script focuses the target, types via wlrctl, then restores
/// the original focus and visible workspaces on all outputs.
#[derive(Parser)]
#[command(name = "send_keypress_to_window")]
struct Args {
	/// Target window app_id (e.g. "com.obsproject.Studio", "foot")
	app_id: String,

	/// Key to send (e.g. "v", "r", "b")
	key: String,
}

#[derive(serde::Deserialize)]
struct SwayCon {
	id: i64,
	app_id: Option<String>,
	focused: Option<bool>,
	nodes: Vec<SwayCon>,
	floating_nodes: Vec<SwayCon>,
}

#[derive(serde::Deserialize)]
struct SwayWorkspace {
	name: String,
	visible: bool,
	output: String,
}

fn find_con(node: &SwayCon, pred: &dyn Fn(&SwayCon) -> bool, results: &mut Vec<i64>) {
	if pred(node) {
		results.push(node.id);
	}
	for child in node.nodes.iter().chain(node.floating_nodes.iter()) {
		find_con(child, pred, results);
	}
}

fn swaymsg_json(args: &[&str]) -> Vec<u8> {
	let output = Command::new("swaymsg").args(args).output().unwrap();
	assert!(output.status.success(), "swaymsg {args:?} failed: {}", String::from_utf8_lossy(&output.stderr));
	output.stdout
}

fn swaymsg(cmd: &str) {
	let output = Command::new("swaymsg").arg(cmd).output().unwrap();
	assert!(output.status.success(), "swaymsg {cmd:?} failed: {}", String::from_utf8_lossy(&output.stderr));
}

fn main() {
	let args = Args::parse();

	// Snapshot state before we touch anything
	let tree: SwayCon = serde_json::from_slice(&swaymsg_json(&["-t", "get_tree"])).unwrap();
	let workspaces: Vec<SwayWorkspace> = serde_json::from_slice(&swaymsg_json(&["-t", "get_workspaces"])).unwrap();

	let mut focused = Vec::new();
	find_con(&tree, &|n| n.focused == Some(true), &mut focused);
	assert!(!focused.is_empty(), "no focused window found");
	let focused_id = focused[0];

	let mut targets = Vec::new();
	find_con(&tree, &|n| n.app_id.as_deref() == Some(&args.app_id), &mut targets);
	assert!(!targets.is_empty(), "no window with app_id '{}' found", args.app_id);
	let target_id = targets[0];

	// Remember which workspace was visible on each output
	let visible_workspaces: Vec<(&str, &str)> = workspaces.iter()
		.filter(|ws| ws.visible)
		.map(|ws| (ws.output.as_str(), ws.name.as_str()))
		.collect();

	// Focus target and type key
	swaymsg(&format!("[con_id={target_id}] focus"));

	let status = Command::new("wlrctl")
		.args(["keyboard", "type", &args.key])
		.status()
		.unwrap();
	assert!(status.success(), "wlrctl keyboard type failed");

	// Restore: bring back the original visible workspace on each output, then refocus
	for (output, ws_name) in &visible_workspaces {
		swaymsg(&format!("focus output {output}; workspace {ws_name}"));
	}
	swaymsg(&format!("[con_id={focused_id}] focus"));
}
