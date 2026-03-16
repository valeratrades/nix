use std::{
	fs,
	io::Write,
	process::Command,
};

/// 3-way merge using `git merge-file`.
/// Takes base (last saved), mine (current buffer), theirs (new disk content).
/// Returns Ok(merged_content) on clean merge, Err(content_with_markers) on conflict.
pub fn three_way_merge(base: String, mine: String, theirs: String) -> Result<String, String> {
	let dir = std::env::temp_dir().join("nvim_autoreload");
	fs::create_dir_all(&dir).expect("failed to create temp dir for autoreload merge");

	let pid = std::process::id();
	let base_path = dir.join(format!("{pid}_base"));
	let mine_path = dir.join(format!("{pid}_mine"));
	let theirs_path = dir.join(format!("{pid}_theirs"));

	let mut f = fs::File::create(&base_path).expect("failed to create base temp file");
	f.write_all(base.as_bytes()).expect("failed to write base temp file");
	drop(f);

	let mut f = fs::File::create(&mine_path).expect("failed to create mine temp file");
	f.write_all(mine.as_bytes()).expect("failed to write mine temp file");
	drop(f);

	let mut f = fs::File::create(&theirs_path).expect("failed to create theirs temp file");
	f.write_all(theirs.as_bytes()).expect("failed to write theirs temp file");
	drop(f);

	// git merge-file: 0 on clean merge, >0 on conflicts. --theirs auto-resolves conflicts.
	let status = Command::new("git")
		.args(["merge-file", "-p", "--theirs"])
		.arg(&mine_path)
		.arg(&base_path)
		.arg(&theirs_path)
		.output()
		.expect("failed to run git merge-file");

	let _ = fs::remove_file(&base_path);
	let _ = fs::remove_file(&mine_path);
	let _ = fs::remove_file(&theirs_path);

	let merged = String::from_utf8_lossy(&status.stdout).into_owned();

	if status.status.success() {
		Ok(merged)
	} else {
		Err(merged)
	}
}
