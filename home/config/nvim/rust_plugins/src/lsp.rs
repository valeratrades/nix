use std::{fs::OpenOptions, io::Write};

use nvim_oxi::{api, Array, Object};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
struct DiagnosticRange {
	start: DiagnosticPosition,
	end: DiagnosticPosition,
}

#[derive(Debug, Serialize, Deserialize)]
struct DiagnosticPosition {
	line: i64,
	character: i64,
}

#[derive(Debug, Serialize, Deserialize)]
struct LspData {
	range: DiagnosticRange,
	source: Option<String>,
	code: Option<String>,
	message: String,
	severity: Option<i64>,
}

#[derive(Debug, Serialize, Deserialize)]
struct UserData {
	lsp: Option<LspData>,
}

#[derive(Debug, Serialize, Deserialize)]
struct Diagnostic {
	lnum: i64,
	bufnr: i64,
	col: i64,
	end_lnum: i64,
	end_col: i64,
	severity: i64,
	message: String,
	source: Option<String>,
	code: Option<String>,
	namespace: Option<i64>,
	user_data: Option<UserData>,
}

/// Diagnostic severity levels (lower number = more severe)
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[repr(i64)]
enum DiagnosticSeverity {
	Error = 1,
	Warning = 2,
	Info = 3,
	Hint = 4,
}

impl From<i64> for DiagnosticSeverity {
	fn from(value: i64) -> Self {
		match value {
			1 => DiagnosticSeverity::Error,
			2 => DiagnosticSeverity::Warning,
			3 => DiagnosticSeverity::Info,
			_ => DiagnosticSeverity::Hint,
		}
	}
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct InterpretedDiagnostic {
	code: Option<String>,
	message: String,
	/// (line, col) - 0-indexed
	start: (i64, i64),
	/// (line, col) - 0-indexed
	end: (i64, i64),
	severity: DiagnosticSeverity,
}

impl From<Diagnostic> for InterpretedDiagnostic {
	fn from(diag: Diagnostic) -> Self {
		// LSP and vim.diagnostic both use 0-indexed positions
		let (start, end) = if let Some(lsp_range) = diag.user_data.as_ref().and_then(|u| u.lsp.as_ref()).map(|l| &l.range) {
			((lsp_range.start.line, lsp_range.start.character), (lsp_range.end.line, lsp_range.end.character))
		} else {
			((diag.lnum, diag.col), (diag.end_lnum, diag.end_col))
		};

		InterpretedDiagnostic {
			code: diag.code,
			message: diag.message,
			start,
			end,
			severity: DiagnosticSeverity::from(diag.severity),
		}
	}
}

/// Echo a message with a highlight type
pub fn echo(text: String, hl_type: Option<String>) {
	let hl = hl_type.unwrap_or_else(|| "Comment".to_string());

	// Capitalize first letter if needed
	let hl_capitalized = if let Some(first_char) = hl.chars().next() {
		if first_char.is_lowercase() {
			let mut chars = hl.chars();
			chars.next();
			format!("{}{}", first_char.to_uppercase(), chars.as_str())
		} else {
			hl
		}
	} else {
		hl
	};

	// Original Lua: vim.api.nvim_echo({{ text, hl }}, false, {})
	let chunks = Array::from_iter(vec![Object::from(Array::from_iter(vec![Object::from(text), Object::from(hl_capitalized)]))]);
	let _ = api::call_function::<_, ()>("nvim_echo", (chunks, false, Array::new()));
}

/// Severity filter for diagnostic navigation
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DiagnosticsFilter {
	/// Navigate to any diagnostic
	All,
	/// Navigate only to the most severe diagnostics present (errors if any, else warnings, etc.)
	Max,
	/// Navigate through all diagnostic levels on the same line as cursor; display only that one
	SameLine,
}
impl From<&str> for DiagnosticsFilter {
	fn from(s: &str) -> Self {
		match s.to_lowercase().as_str() {
			"all" => DiagnosticsFilter::All,
			"max" => DiagnosticsFilter::Max,
			"same_line" => DiagnosticsFilter::SameLine,
			_ => unimplemented!(),
		}
	}
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Direction {
	Reverse,
	Forward,
}
impl From<i64> for Direction {
	fn from(i: i64) -> Self {
		match i {
			1 => Direction::Forward,
			-1 => Direction::Reverse,
			_ => panic!("\"{i}\" for direction is not supported"),
		}
	}
}

/// Jump to diagnostic in the given direction
/// direction: 1 for next, -1 for prev
/// request_severity: "all" to include all severities, "max" for only most severe
// Module-level debug logging helper
fn debug_log(msg: String) {
	let log_path_tilde = "~/.local/state/nvim/rust_plugins/jump_to_diagnostic.log";
	let log_path: String = api::call_function("expand", (log_path_tilde,)).unwrap_or_else(|_| log_path_tilde.to_string());

	let mut file = OpenOptions::new().create(true).append(true).open(&log_path).unwrap();
	writeln!(file, "{msg}").unwrap();
}

//TODO: impl logic for sideways movement inside the same line with <C-s>/<C-t>
pub fn jump_to_diagnostic(direction: i64, request_severity: String) {
	let diagnostics_filter = DiagnosticsFilter::from(request_severity.as_str());
	let direction = Direction::from(direction);

	let _ = std::panic::catch_unwind(|| {
		// Setup log file - expand ~ and create directory
		let log_path_tilde = "~/.local/state/nvim/rust_plugins/jump_to_diagnostic.log";
		let log_path: String = api::call_function("expand", (log_path_tilde,)).unwrap_or_else(|_| log_path_tilde.to_string());

		// Create parent directory if needed
		if let Some(parent) = std::path::Path::new(&log_path).parent() {
			let _ = std::fs::create_dir_all(parent);
		}

		// Append separator between entries
		{
			let mut file = OpenOptions::new().create(true).write(true).truncate(true).open(&log_path).unwrap();
			writeln!(file, "\n\n======").unwrap();
		}

		// Log cursor position
		let cursor_line: i64 = api::call_function("line", (".",)).unwrap_or(0);
		let cursor_col: i64 = api::call_function("col", (".",)).unwrap_or(0);
		debug_log(format!("Cursor position: line={cursor_line}, col={cursor_col}"));

		let bufnr = api::get_current_buf();
		let bufnr_handle = bufnr.handle();
		let diagnostics = get_buffer_diagnostics(bufnr);
		if diagnostics.is_empty() {
			echo("no diagnostics in 0".to_string(), Some("Comment".to_string()));
			return;
		}

		debug_log(format!("\n=== DIAGNOSTICS ({} total) ===", diagnostics.len()));

		// Get file line count and last line length (Lua line("$") is 1-indexed, convert to 0-indexed)
		let line_count_1idx: i64 = api::call_function("line", ("$",)).unwrap_or(1);
		let last_line_idx = line_count_1idx - 1; // 0-indexed
		let last_line_col: i64 = {
			// Get the actual text of the last line and measure its length (getline expects 1-indexed)
			let lua_code = format!("vim.fn.strlen(vim.fn.getline({line_count_1idx}))");
			api::call_function("luaeval", (lua_code,)).unwrap_or(0)
		};
		debug_log(format!("File has {} lines (0-idx: 0..={}), last line ends at col {}", line_count_1idx, last_line_idx, last_line_col));

		// Parse and interpret all diagnostics first
		let mut interpreted_diagnostics: Vec<InterpretedDiagnostic> = Vec::new();
		debug_log("\n=== RAW DIAGNOSTICS (JSON) ===".to_string());
		for i in 0..diagnostics.len() {
			let lua_code = format!("vim.fn.json_encode(vim.diagnostic.get({})[{}])", bufnr_handle, i + 1); // Lua is 1-indexed
			if let Ok(json_str) = api::call_function::<_, String>("luaeval", (lua_code,)) {
				// Pretty-print the raw JSON
				if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&json_str) {
					debug_log(format!("[{}] {}", i, serde_json::to_string_pretty(&parsed).unwrap_or(json_str.clone())));
				}
				if let Ok(diag) = serde_json::from_str::<Diagnostic>(&json_str) {
					let mut interpreted = InterpretedDiagnostic::from(diag);

					// Clamp diagnostic positions to file boundaries (0-indexed)
					if interpreted.start.0 > last_line_idx {
						debug_log(format!(
							"Clamping diagnostic start from ({}, {}) to ({}, {})",
							interpreted.start.0, interpreted.start.1, last_line_idx, last_line_col
						));
						interpreted.start = (last_line_idx, last_line_col);
					}
					if interpreted.end.0 > last_line_idx {
						debug_log(format!(
							"Clamping diagnostic end from ({}, {}) to ({}, {})",
							interpreted.end.0, interpreted.end.1, last_line_idx, last_line_col
						));
						interpreted.end = (last_line_idx, last_line_col);
					}

					interpreted_diagnostics.push(interpreted);
				}
			}
		}

		// Deduplicate diagnostics (same severity, code, message, position from different sources)
		{
			use std::collections::HashSet;
			let mut seen: HashSet<InterpretedDiagnostic> = HashSet::new();
			interpreted_diagnostics.retain(|d| seen.insert(d.clone()));
		}

		// log diagnostics state
		debug_log("\n\n\n\n\n\n\n\n\n\n=== INTERPRETED DIAGNOSTICS ===".to_string());
		{
			// Group by line (1-indexed now)
			use std::collections::HashMap;
			let mut by_line: HashMap<i64, Vec<&InterpretedDiagnostic>> = HashMap::new();
			for diag in &interpreted_diagnostics {
				by_line.entry(diag.start.0).or_insert_with(Vec::new).push(diag);
			}

			// Sort lines and display
			let mut lines: Vec<_> = by_line.keys().copied().collect();
			lines.sort_unstable();

			for line_num in lines {
				let diags_on_line = &by_line[&line_num];
				debug_log(format!("\n--- Line {line_num} ({} diagnostics) ---", diags_on_line.len()));

				for diag in diags_on_line {
					debug_log(format!(
						"  start: {:?}\n  end: {:?}\n  code: {:?}\n  message: {}\n",
						diag.start, diag.end, diag.code, diag.message
					));
				}
			}
			debug_log("-----------------------------------------------------------------".to_string());
		}

		// Filter diagnostics based on diagnostics_filter
		debug_log(format!("diagnostics_filter: {:?}, direction: {:?}", diagnostics_filter, direction));
		let relevant_diagnostics: Vec<&InterpretedDiagnostic> = match diagnostics_filter {
			DiagnosticsFilter::Max => {
				// Find the most severe (minimum) severity present, then include all diagnostics at that level or more severe
				let most_severe_present = interpreted_diagnostics.iter().map(|d| d.severity).min().unwrap_or(DiagnosticSeverity::Hint);
				interpreted_diagnostics.iter().filter(|d| d.severity <= most_severe_present).collect()
			}
			_ => interpreted_diagnostics.iter().collect(),
		};

		// Lua line()/col() are 1-indexed, convert to 0-indexed
		let current_line: i64 = api::call_function::<_, i64>("line", (".",)).unwrap_or(1) - 1;
		let current_col: i64 = api::call_function::<_, i64>("col", (".",)).unwrap_or(1) - 1;
		let current_pos = (current_line, current_col);

		let is_popup_open = || {
			let popups = crate::remap::get_popups();
			!popups.is_empty()
		};

		let nav_to: Option<(i64, Option<i64>)> = match diagnostics_filter {
			DiagnosticsFilter::SameLine => {
				// Get diagnostics on current line only, sorted by column
				let mut diags_on_line: Vec<&InterpretedDiagnostic> = interpreted_diagnostics
					.iter()
					.filter(|d| d.start.0 == current_line)
					.collect();
				diags_on_line.sort_by_key(|d| d.start.1);

				if diags_on_line.is_empty() {
					// No diagnostics on this line
					None
				} else {
					let on_exact_diagnostic = diags_on_line.iter().any(|d| d.start == current_pos);
					if on_exact_diagnostic && !is_popup_open() {
						// Already on a diagnostic, no popup open - just show popup at current position
						None
					} else {
						// Find next/prev diagnostic column on this line
						// Use unique columns only for navigation
						let cols: Vec<i64> = {
							use std::collections::BTreeSet;
							diags_on_line.iter().map(|d| d.start.1).collect::<BTreeSet<_>>().into_iter().collect()
						};
						let target_col = match direction {
							Direction::Forward => {
								// Find first col > current_col, or wrap to first
								cols.iter()
									.find(|&&c| c > current_col)
									.copied()
									.unwrap_or(*cols.first().unwrap())
							}
							Direction::Reverse => {
								// Find last col < current_col, or wrap to last
								cols.iter()
									.rev()
									.find(|&&c| c < current_col)
									.copied()
									.unwrap_or(*cols.last().unwrap())
							}
						};
						Some((current_line, Some(target_col)))
					}
				}
			},
			_ => match !is_popup_open() && interpreted_diagnostics.iter().any(|d| d.start.0 == current_line) {
				true => None,
				false => {
					//Q: does it really make sense to shove the last diagnostic in the file, if outside of the last line, onto the previous? Or should I only make that adj inside the nav_to.is_some()?

					let target_line = {
						// Get all unique lines with diagnostics
						use std::collections::HashSet;
						let mut lines_with_diagnostics: Vec<i64> = relevant_diagnostics.iter().map(|d| d.start.0).collect::<HashSet<_>>().into_iter().collect();
						debug_log(format!("relevant_diagnostics count: {}, lines_with_diagnostics: {:?}", relevant_diagnostics.len(), lines_with_diagnostics));
						lines_with_diagnostics.sort_unstable();
						match direction {
							Direction::Forward => {
								// Next: find first line > current_line, or wrap to first
								lines_with_diagnostics
									.iter()
									.find(|&&l| l > current_line)
									.copied()
									.unwrap_or(*lines_with_diagnostics.first().unwrap_or(&current_line))
							}
							Direction::Reverse => {
								// Prev: find last line < current_line, or wrap to last
								lines_with_diagnostics
									.iter()
									.rev()
									.find(|&&l| l < current_line)
									.copied()
									.unwrap_or(*lines_with_diagnostics.last().unwrap_or(&current_line))
							}
						}
					};
					Some((target_line, None))
				}
			}
		};
		if let Some((line, maybe_col)) = nav_to {
			// getcurpos() returns [bufnum, lnum, col, off, curswant] - all 1-indexed
			let curpos: Vec<i64> = api::call_function("getcurpos", ((),)).unwrap_or_default();
			let [bufnr, _lnum, _col, off, curswant] = curpos[..] else { panic!("getcurpos returned {} elements", curpos.len()) };
			debug_log(format!("{curpos:?}"));
			// nav_to is 0-indexed, curswant is 1-indexed
			let col = match maybe_col {
				Some(c) => c + 1, // convert 0-indexed to 1-indexed for Lua
				None => curswant, // already 1-indexed from getcurpos
			};
			// Convert line from 0-indexed to 1-indexed for Lua
			let line_1idx = line + 1;
			debug_log(format!("nav_to: line={} (0-idx), col={} (1-idx)", line, col));
			// cursor(lnum, col) expects 1-indexed
			let result: Result<i64, _> = api::call_function("cursor", (line_1idx, col));
			// setpos('.', [bufnr, lnum, col, off, curswant]) expects 1-indexed
			let pos = Array::from_iter([bufnr, line_1idx, col, off, curswant]);
			let _: Result<(), _> = api::call_function("setpos", (".", pos));
			// Force redraw so cursor position is updated before popup positioning
			let _: Result<(), _> = api::command("redraw");
			debug_log(format!("cursor() result: {:?}", result));
			let after: i64 = api::call_function("line", (".",)).unwrap_or(-1);
			debug_log(format!("after cursor(): line={} (1-idx)", after));
		}

		// Get the line we're showing diagnostics for (either where we navigated to, or current line)
		let display_line = nav_to.map(|(line, _)| line).unwrap_or(current_line);

		// Get current position after navigation (Lua col() is 1-indexed, convert to 0-indexed)
		let display_col: i64 = api::call_function::<_, i64>("col", (".",)).unwrap_or(1) - 1;

		let diagnostics_to_show: Vec<DiagLine> = {
			let mut diagnostics_to_display: Vec<&InterpretedDiagnostic> = match diagnostics_filter {
				DiagnosticsFilter::SameLine => {
					// Only show diagnostic(s) at exact current position
					interpreted_diagnostics
						.iter()
						.filter(|d| d.start == (display_line, display_col))
						.collect()
				}
				_ => {
					// Show all diagnostics on the target line
					interpreted_diagnostics
						.iter()
						.filter(|d| d.start.0 == display_line)
						.collect()
				}
			};
			// Sort by severity (Error=1 first, then Warning=2, Info=3, Hint=4)
			diagnostics_to_display.sort_by_key(|d| d.severity);

			// Build lines with severity info for highlighting
			diagnostics_to_display
				.iter()
				.enumerate()
				.flat_map(|(i, d)| {
					let prefix = format!("{}. ", i + 1);
					let prefix_len = prefix.len();
					let code_suffix = d.code.as_ref().map(|c| format!(" [{c}]")).unwrap_or_default();
					let header = format!("{}{}{}", prefix, d.message.lines().next().unwrap_or(""), code_suffix);
					let rest: Vec<DiagLine> = d
						.message
						.lines()
						.skip(1)
						.map(|s| DiagLine {
							text: s.to_string(),
							severity: None,
							prefix_len: 0,
						})
						.collect();
					std::iter::once(DiagLine {
						text: header,
						severity: Some(d.severity),
						prefix_len,
					})
					.chain(rest)
				})
				.collect()
		};

		// Display
		{
			if nav_to.is_some() {
				// if None, it's because we are already there but no existing popup, - so nothing to close
				crate::remap::kill_popups();
			}
			debug_log(format!(
				"\n=== OPENING FLOAT ===\n{} diagnostics to show",
				diagnostics_to_show.len()
			));
			show_diagnostic_float(diagnostics_to_show);
		}
		return;
	});
}

/// Get diagnostics for a buffer
fn get_buffer_diagnostics(bufnr: nvim_oxi::api::Buffer) -> Vec<nvim_oxi::Dictionary> {
	// Use luaeval to call vim.diagnostic.get
	let lua_code = format!("vim.diagnostic.get({})", bufnr.handle());
	match api::call_function("luaeval", (lua_code,)) {
		Ok(arr) => {
			let array: nvim_oxi::Array = arr;
			array.into_iter().filter_map(|obj| nvim_oxi::Dictionary::try_from(obj).ok()).collect()
		}
		Err(e) => {
			echo(format!("Error getting diagnostics: {}", e), Some("ErrorMsg".to_string()));
			vec![]
		}
	}
}

struct DiagLine {
	text: String,
	severity: Option<DiagnosticSeverity>, // Some(severity) for header lines, None for continuation
	prefix_len: usize,                    // Length of "N. " prefix to highlight
}

/// Show diagnostic lines in a float with severity-colored prefixes, positioned near cursor
fn show_diagnostic_float(diag_lines: Vec<DiagLine>) {
	use crate::utils::{show_popup_with_options, LineHighlight, PopupOptions};

	// Build text content
	let text = diag_lines.iter().map(|dl| dl.text.as_str()).collect::<Vec<_>>().join("\n");

	// Build highlights
	let highlights: Vec<LineHighlight> = diag_lines
		.iter()
		.enumerate()
		.filter_map(|(line_idx, dl)| {
			dl.severity.map(|sev| {
				let hl_group = match sev {
					DiagnosticSeverity::Error => "DiagnosticError",
					DiagnosticSeverity::Warning => "DiagnosticWarn",
					DiagnosticSeverity::Info => "DiagnosticInfo",
					DiagnosticSeverity::Hint => "DiagnosticHint",
				};
				LineHighlight {
					line: line_idx,
					col_start: 0,
					col_end: dl.prefix_len,
					hl_group: hl_group.to_string(),
				}
			})
		})
		.collect();

	show_popup_with_options(text, PopupOptions { sticky: true, highlights });
}

/// Yank the contents of the diagnostic popup to system clipboard
pub fn yank_diagnostic_popup() {
	let popups = crate::remap::get_popups();

	if popups.len() == 1 {
		let popup_id = popups[0];

		// Get buffer from window
		let bufnr: i64 = api::call_function("nvim_win_get_buf", (popup_id,)).unwrap_or(0);

		// Get lines from buffer
		let lines: Vec<String> = api::call_function("nvim_buf_get_lines", (bufnr, 0, -1, false)).unwrap_or_else(|_| vec![]);

		// Join lines and set to clipboard
		let content = lines.join("\n");
		let _: () = api::call_function("setreg", ("+", content)).unwrap_or(());
	}
}
