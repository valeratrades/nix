#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::Parser;
use std::io::{self, Read};
use std::fs;
use std::path::PathBuf;

/// Wrap text to a specified line width
#[derive(Parser, Debug)]
#[command(name = "wrap_output")]
#[command(about = "Wrap text lines to a specified width")]
struct Args {
	/// Input: file path, literal string, or '-' for stdin
	input: String,

	/// Maximum line width
	#[arg(short = 'l', long, default_value = "120")]
	width: usize,
}

fn wrap_lines(text: &str, max_width: usize) -> String {
	text.lines()
		.map(|line| wrap_single_line(line, max_width))
		.collect::<Vec<_>>()
		.join("\n")
}

fn wrap_single_line(line: &str, max_width: usize) -> String {
	if line.len() <= max_width {
		return line.to_string();
	}

	// Count leading whitespace for continuation indent
	let leading_ws: String = line.chars().take_while(|c| c.is_whitespace()).collect();
	let continuation_indent = format!("{leading_ws}  "); // 2 extra spaces for wrapped lines

	let mut result = String::new();
	let mut current_line = String::new();
	let mut first_line = true;

	for word in line.split_whitespace() {
		let prefix = if first_line { &leading_ws } else { &continuation_indent };

		// Check if adding this word would exceed max_width
		let test_line = if current_line.is_empty() {
			format!("{prefix}{word}")
		} else {
			format!("{current_line} {word}")
		};

		if test_line.len() > max_width && !current_line.is_empty() {
			// Push current line and start new one
			if !result.is_empty() {
				result.push('\n');
			}
			result.push_str(&current_line);
			current_line = format!("{continuation_indent}{word}");
			first_line = false;
		} else {
			current_line = test_line;
		}
	}

	// Don't forget the last line
	if !current_line.is_empty() {
		if !result.is_empty() {
			result.push('\n');
		}
		result.push_str(&current_line);
	}

	result
}

fn main() {
	let args = Args::parse();

	let text = if args.input == "-" {
		// Read from stdin
		let mut buffer = String::new();
		io::stdin().read_to_string(&mut buffer).expect("Failed to read from stdin");
		buffer
	} else {
		let path = PathBuf::from(&args.input);
		if path.exists() {
			// Read from file
			fs::read_to_string(&path).expect("Failed to read file")
		} else {
			// Treat as literal string
			args.input.clone()
		}
	};

	print!("{}", wrap_lines(&text, args.width));
}
