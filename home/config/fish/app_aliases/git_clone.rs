#!/usr/bin/env -S cargo -Zscript -q

use std::{
	env,
	path::{Path, PathBuf},
	process::{Command, exit},
};

fn clone_repo(args: &[String]) -> Result<PathBuf, String> {
	let github_username = env::var("GITHUB_USERNAME").ok();

	let repo_payload = args[0].trim_end_matches("/").to_string();
	let repo = if let Some((owner, repo)) = repo_payload.split_once('/') {
		format!("{}/{}", owner, repo)
	} else if let Some(username) = github_username {
		format!("{}/{}", username, repo_payload)
	} else {
		return Err("Owner is missing in the repository name, and $GITHUB_USERNAME is not set".to_string());
	};

	let url = if args[0].contains("://") {
		repo_payload.clone()
	} else {
		format!("https://github.com/{}", repo)
	};

	let filename = Path::new(&url)
		.file_name()
		.map(|f| f.to_string_lossy().to_string())
		.unwrap_or_default()
		.trim_end_matches(".git")
		.to_string();

	if args.len() == 1 {
		let tmp_path = format!("/tmp/{}", filename);
		if env::current_dir().unwrap().to_str() == Some(&tmp_path) {
			Command::new("cd").arg("-").output().ok();
		}
		Command::new("rm")
			.arg("-rf")
			.arg(&tmp_path)
			.status()
			.map_err(|_| "Failed to remove existing directory".to_string())?;

		let status = Command::new("git")
			.args(["clone", "--depth=1", &url, &tmp_path])
			.status()
			.map_err(|_| "Failed to run git clone".to_string())?;

		if status.success() {
			env::set_current_dir(&tmp_path).map_err(|_| "Failed to change directory".to_string())?;
			Ok(env::current_dir().unwrap())
		} else {
			Err("Git clone failed".to_string())
		}
	} else if args.len() == 2 {
		let target = if Path::new(&args[1]).is_dir() {
			PathBuf::from(args[1].clone()).join(filename)
		} else {
			PathBuf::from(args[1].clone())
		};

		let status = Command::new("git")
			.args(["clone", "--depth=1", &url, &target.display().to_string()])
			.status()
			.map_err(|_| "Failed to run git clone".to_string())?;

		if status.success() { Ok(target) } else { Err("Git clone failed".to_string()) }
	} else {
		Err("Invalid number of arguments".to_string())
	}
}

fn main() {
	let args: Vec<String> = env::args().skip(1).collect();
	let help_message = "\
git clone on rails.
give repo name, it clones into /tmp or provided directory.

ex 1: gc neovim/neovim . # will clone to current directory
ex 2: gc neovim/neovim # will clone to /tmp/neovim";

	if args.is_empty() || matches!(args[0].as_str(), "-h" | "--help" | "help") {
		println!("{}", help_message);
		return;
	}

	match clone_repo(&args) {
		Ok(message) => println!("{}", message.display()),
		Err(error) => {
			eprintln!("{}", error);
			exit(1);
		}
	}
}
