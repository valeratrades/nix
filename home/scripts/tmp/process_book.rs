#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4", features = ["derive"] }
regex = "1"
eyre = "0.6"
tokio = { version = "1", features = ["rt-multi-thread","macros","process","fs","io-util","time","sync"] }
quick-xml = "0.36"
---

use clap::{Parser, Subcommand};
use eyre::{Result, eyre};
use quick_xml::events::Event;
use quick_xml::Reader;
use regex::Regex;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::{Arc, OnceLock};
use std::{fmt, fs};
use tokio::process::Command;
use tokio::sync::Semaphore;

#[derive(Parser)]
struct Args {
	/// Input book file (.txt or .fb2)
	#[arg(short, long)]
	file: PathBuf,
	/// Chapter heading pattern (only for .txt files)
	#[arg(long)]
	chapter_pattern: Option<String>,
	/// Max parallel jobs
	#[arg(long, default_value_t = 2)]
	max_jobs: usize,
	/// Base directory for output (defaults to current directory)
	#[arg(short = 'd', long, default_value = ".")]
	dir: PathBuf,
	#[command(subcommand)]
	cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
	/// Split book into chapters
	Parse,
	/// Run book_parser + translate_infrequent on chapters
	Translate {
		#[arg(short, long)]
		wlimit: String,
		/// First chapter to translate (inclusive)
		#[arg(long)]
		since: Option<u32>,
		/// Last chapter to translate (inclusive)
		#[arg(long)]
		until: Option<u32>,
	},
	/// Join translated chapters into final output
	Compile,
}

#[derive(Clone)]
struct PageRange {
	since: Option<u32>,
	until: Option<u32>,
}

impl PageRange {
	fn contains(&self, n: u32) -> bool {
		self.since.map_or(true, |s| n >= s) && self.until.map_or(true, |u| n <= u)
	}
}

impl fmt::Display for PageRange {
	fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
		match (self.since, self.until) {
			(Some(s), Some(u)) => write!(f, "_{s}..={u}"),
			(Some(s), None) => write!(f, "_{s}.."),
			(None, Some(u)) => write!(f, "_..={u}"),
			(None, None) => Ok(()),
		}
	}
}

fn book_root(base: &Path, stem: &str) -> &'static PathBuf {
	static ROOT: OnceLock<PathBuf> = OnceLock::new();
	ROOT.get_or_init(|| base.join(stem))
}

fn collect_numbered(dir: &Path, prefix: &str, suffix: &str) -> Result<Vec<(u32, PathBuf)>> {
	let num_re = Regex::new(r"([0-9]+)").unwrap();
	let mut v = Vec::new();
	if !dir.exists() {
		return Ok(v);
	}
	for e in fs::read_dir(dir)? {
		let e = e?;
		let p = e.path();
		if !p.is_file() {
			continue;
		}
		let name = e.file_name().to_string_lossy().to_string();
		if name.starts_with(prefix) && name.ends_with(suffix) {
			if let Some(c) = num_re.captures(&name) {
				if let Ok(n) = c[1].parse::<u32>() {
					v.push((n, p));
				}
			}
		}
	}
	v.sort_by_key(|(n, _)| *n);
	Ok(v)
}

fn glob_fails(dir: &Path) -> Result<Vec<PathBuf>> {
	let mut v = Vec::new();
	if !dir.exists() {
		return Ok(v);
	}
	for e in fs::read_dir(dir)? {
		let e = e?;
		let p = e.path();
		if p.is_file() && p.extension().is_some_and(|x| x == "fail") {
			v.push(p);
		}
	}
	Ok(v)
}

// --- parsing ---

fn split_txt(input: &Path, chapter_re: &Regex, outdir: &Path) -> Result<()> {
	let f = fs::File::open(input)?;
	let r = BufReader::new(f);
	let num_re = Regex::new(r"[0-9]+").unwrap();
	let mut out: Option<fs::File> = None;
	for line in r.lines() {
		let line = line?;
		if chapter_re.is_match(&line) {
			if let Some(m) = num_re.find(&line) {
				let num = &line[m.start()..m.end()];
				out = Some(fs::File::create(outdir.join(format!("chapter_{num}.txt")))?);
			}
		}
		if let Some(fh) = out.as_mut() {
			fh.write_all(line.as_bytes())?;
			fh.write_all(b"\n")?;
		}
	}
	Ok(())
}

fn split_fb2(input: &Path, outdir: &Path) -> Result<()> {
	let content = fs::read_to_string(input)?;
	let mut reader = Reader::from_str(&content);
	reader.config_mut().trim_text(true);

	let num_re = Regex::new(r"[0-9]+").unwrap();
	let mut buf = Vec::new();
	let mut in_body = false;
	let mut section_depth: u32 = 0;
	let mut in_section = false;
	let mut in_title = false;
	let mut current_chapter: Option<(u32, fs::File)> = None;
	let mut current_text = String::new();

	loop {
		match reader.read_event_into(&mut buf) {
			Ok(Event::Start(e)) => {
				let name = e.name();
				if name.as_ref() == b"body" {
					in_body = true;
				} else if in_body && name.as_ref() == b"section" {
					section_depth += 1;
					if section_depth == 1 {
						in_section = true;
						current_text.clear();
					}
				} else if in_section && name.as_ref() == b"title" {
					in_title = true;
				}
			}
			Ok(Event::End(e)) => {
				let name = e.name();
				if name.as_ref() == b"body" {
					in_body = false;
				} else if name.as_ref() == b"section" {
					if section_depth == 1 {
						in_section = false;
						current_chapter = None;
					}
					section_depth = section_depth.saturating_sub(1);
				} else if name.as_ref() == b"title" {
					in_title = false;
				} else if in_section && name.as_ref() == b"p" {
					if let Some((_, ref mut file)) = current_chapter {
						file.write_all(current_text.as_bytes())?;
						file.write_all(b"\n")?;
						current_text.clear();
					}
				}
			}
			Ok(Event::Text(e)) => {
				if in_section {
					let text = e.unescape().unwrap_or_default();
					if in_title && current_chapter.is_none() {
						if let Some(m) = num_re.find(&text) {
							let num: u32 = text[m.start()..m.end()].parse().unwrap();
							let file =
								fs::File::create(outdir.join(format!("chapter_{num}.txt")))?;
							current_chapter = Some((num, file));
						}
					} else if current_chapter.is_some() {
						current_text.push_str(&text);
					}
				}
			}
			Ok(Event::Eof) => break,
			Err(e) => {
				return Err(eyre!(
					"Error parsing FB2 at position {}: {e:?}",
					reader.buffer_position()
				))
			}
			_ => {}
		}
		buf.clear();
	}
	Ok(())
}

// --- translation ---

async fn run_book_parser(ch: &Path, num: u32, de_dir: &Path, fail_dir: &Path) -> Result<()> {
	let de = de_dir.join(format!("chapter_{num}.txt"));
	let status = Command::new("sh")
		.arg("-c")
		.arg(format!(
			"book_parser -l German -f '{}' > '{}'",
			ch.display(),
			de.display()
		))
		.stdout(Stdio::null())
		.stderr(Stdio::null())
		.status()
		.await?;
	if !status.success() {
		fs::write(fail_dir.join(format!("chapter_{num}.fail")), format!("{num}\n"))?;
		return Err(eyre!("book_parser failed for chapter {num}"));
	}
	Ok(())
}

async fn run_translate(
	num: u32,
	wlimit: &str,
	de_dir: &Path,
	ti_dir: &Path,
	fail_dir: &Path,
) -> Result<()> {
	let de = de_dir.join(format!("chapter_{num}.txt"));
	let ti = ti_dir.join(format!("chapter_{num}.txt"));
	let cmd = format!(
		"translate_infrequent -l de -w {} < '{}' > '{}'",
		shell_escape(wlimit),
		de.display(),
		ti.display()
	);
	let status = Command::new("sh")
		.arg("-c")
		.arg(cmd)
		.stdout(Stdio::null())
		.stderr(Stdio::null())
		.status()
		.await?;
	if !status.success() {
		fs::write(
			fail_dir.join(format!("chapter_{num}.fail")),
			format!("{num}\n"),
		)?;
		return Err(eyre!("translate_infrequent failed for chapter {num}"));
	}
	Ok(())
}

fn shell_escape(s: &str) -> String {
	if s.bytes().all(|b| b.is_ascii_alphanumeric()) {
		return s.to_string();
	}
	format!("'{}'", s.replace('\'', r"'\''"))
}

// --- compile ---

fn join_markdown(chapters: &[(u32, PathBuf)], out: &Path) -> Result<()> {
	let mut f = fs::File::create(out)?;
	for (i, (num, path)) in chapters.iter().enumerate() {
		if i > 0 {
			f.write_all(b"\n\n")?;
		}
		writeln!(f, "# Глава {num}")?;
		let mut src = BufReader::new(fs::File::open(path)?);
		let mut buf = Vec::new();
		src.read_to_end(&mut buf)?;
		f.write_all(&buf)?;
	}
	Ok(())
}

fn join_fb2(chapters: &[(u32, PathBuf)], out: &Path) -> Result<()> {
	let mut f = fs::File::create(out)?;
	writeln!(f, r#"<?xml version="1.0" encoding="utf-8"?>"#)?;
	writeln!(f, r#"<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">"#)?;
	writeln!(f, "  <description>")?;
	writeln!(f, "    <title-info>")?;
	writeln!(f, "      <genre>prose</genre>")?;
	writeln!(
		f,
		"      <author><first-name>Unknown</first-name><last-name>Author</last-name></author>"
	)?;
	writeln!(f, "      <book-title>Translated Book</book-title>")?;
	writeln!(f, "      <lang>ti</lang>")?;
	writeln!(f, "    </title-info>")?;
	writeln!(f, "  </description>")?;
	writeln!(f, "  <body>")?;
	for (num, path) in chapters {
		writeln!(f, "    <section>")?;
		writeln!(f, "      <title><p>ምዕራፍ {num}</p></title>")?;
		let content = fs::read_to_string(path)?;
		for line in content.lines() {
			let trimmed = line.trim();
			if !trimmed.is_empty() {
				writeln!(f, "      <p>{}</p>", escape_xml(trimmed))?;
			}
		}
		writeln!(f, "    </section>")?;
	}
	writeln!(f, "  </body>")?;
	writeln!(f, "</FictionBook>")?;
	Ok(())
}

fn escape_xml(s: &str) -> String {
	s.replace('&', "&amp;")
		.replace('<', "&lt;")
		.replace('>', "&gt;")
		.replace('"', "&quot;")
		.replace('\'', "&apos;")
}

#[tokio::main(flavor = "multi_thread")]
async fn main() -> Result<()> {
	let args = Args::parse();

	if !args.file.exists() {
		return Err(eyre!("file '{}' does not exist", args.file.display()));
	}

	let ext = args
		.file
		.extension()
		.and_then(|e| e.to_str())
		.ok_or_else(|| eyre!("input file has no extension"))?;
	match ext {
		"txt" | "fb2" => {}
		_ => return Err(eyre!("unsupported extension '.{ext}', expected .txt or .fb2")),
	}

	let stem = args
		.file
		.file_stem()
		.ok_or_else(|| eyre!("input file has no stem"))?
		.to_string_lossy()
		.to_string();

	let root = book_root(&args.dir, &stem);
	let split = root.join("chapters_split");
	let de = root.join("chapters_de");
	let ti = root.join("chapters_ti");
	let fbp = root.join("failed_book_parser");
	let fti = root.join("failed_translate");

	match args.cmd {
		Cmd::Parse => {
			fs::create_dir_all(&split)?;

			match ext {
				"txt" => {
					let pattern = args
						.chapter_pattern
						.as_deref()
						.unwrap_or(r"^Глава [0-9]+");
					let re = Regex::new(pattern)?;
					split_txt(&args.file, &re, &split)?;
				}
				"fb2" => {
					if args.chapter_pattern.is_some() {
						return Err(eyre!("--chapter-pattern is not applicable to .fb2 files"));
					}
					split_fb2(&args.file, &split)?;
				}
				_ => unreachable!(),
			}

			let chapters = collect_numbered(&split, "chapter_", ".txt")?;
			println!("parsed {} chapters", chapters.len());
		}

		Cmd::Translate {
			wlimit,
			since,
			until,
		} => {
			if !split.exists() {
				return Err(eyre!(
					"chapters_split not found at '{}' — run `parse` first",
					split.display()
				));
			}

			let range = PageRange { since, until };
			fs::create_dir_all(&de)?;
			fs::create_dir_all(&ti)?;
			fs::create_dir_all(&fbp)?;
			fs::create_dir_all(&fti)?;

			let all_chapters = collect_numbered(&split, "chapter_", ".txt")?;
			let chapters: Vec<_> = all_chapters
				.into_iter()
				.filter(|(n, _)| range.contains(*n))
				.collect();

			println!(
				"translating {} chapters{}",
				chapters.len(),
				if since.is_some() || until.is_some() {
					format!(" (range: {range})")
				} else {
					String::new()
				}
			);

			let sem = Arc::new(Semaphore::new(args.max_jobs));

			// book_parser pass
			{
				let mut tasks = Vec::new();
				for (num, path) in &chapters {
					let num = *num;
					let path = path.clone();
					let de = de.clone();
					let fbp = fbp.clone();
					let permit = sem.clone().acquire_owned().await.unwrap();
					tasks.push(tokio::spawn(async move {
						let _p = permit;
						run_book_parser(&path, num, &de, &fbp).await
					}));
				}
				for t in tasks {
					t.await.unwrap()?;
				}
			}

			// translate pass
			{
				let mut tasks = Vec::new();
				let des = collect_numbered(&de, "chapter_", ".txt")?;
				let filtered: Vec<_> =
					des.into_iter().filter(|(n, _)| range.contains(*n)).collect();
				for (num, _) in &filtered {
					let num = *num;
					let wlimit = wlimit.clone();
					let de = de.clone();
					let ti = ti.clone();
					let fti = fti.clone();
					let permit = sem.clone().acquire_owned().await.unwrap();
					tasks.push(tokio::spawn(async move {
						let _p = permit;
						run_translate(num, &wlimit, &de, &ti, &fti).await
					}));
				}
				for t in tasks {
					t.await.unwrap()?;
				}
			}

			// retry book_parser failures
			{
				let fails = glob_fails(&fbp)?;
				if !fails.is_empty() {
					let mut tasks = Vec::new();
					for fail in fails {
						let num: u32 = fs::read_to_string(&fail)?.trim().parse()?;
						if !range.contains(num) {
							continue;
						}
						let _ = fs::remove_file(de.join(format!("chapter_{num}.txt")));
						let _ = fs::remove_file(ti.join(format!("chapter_{num}.txt")));
						let _ = fs::remove_file(&fail);
						let ch = split.join(format!("chapter_{num}.txt"));
						let de = de.clone();
						let fbp = fbp.clone();
						let permit = sem.clone().acquire_owned().await.unwrap();
						tasks.push(tokio::spawn(async move {
							let _p = permit;
							run_book_parser(&ch, num, &de, &fbp).await
						}));
					}
					for t in tasks {
						t.await.unwrap()?;
					}
				}
			}

			// retry translate failures
			{
				let fails = glob_fails(&fti)?;
				if !fails.is_empty() {
					let mut tasks = Vec::new();
					for fail in fails {
						let num: u32 = fs::read_to_string(&fail)?.trim().parse()?;
						if !range.contains(num) {
							continue;
						}
						let _ = fs::remove_file(ti.join(format!("chapter_{num}.txt")));
						let _ = fs::remove_file(&fail);
						let wlimit = wlimit.clone();
						let de = de.clone();
						let ti = ti.clone();
						let fti = fti.clone();
						let permit = sem.clone().acquire_owned().await.unwrap();
						tasks.push(tokio::spawn(async move {
							let _p = permit;
							run_translate(num, &wlimit, &de, &ti, &fti).await
						}));
					}
					for t in tasks {
						t.await.unwrap()?;
					}
				}
			}

			println!("translation done");
		}

		Cmd::Compile => {
			let parsed = collect_numbered(&split, "chapter_", ".txt")?;
			let translated = collect_numbered(&ti, "chapter_", ".txt")?;

			if translated.is_empty() {
				return Err(eyre!("no translated chapters found"));
			}

			// infer range: if translated is a strict subset of parsed, derive since/until
			let range = if translated.len() < parsed.len() {
				let first_t = translated.first().unwrap().0;
				let last_t = translated.last().unwrap().0;
				let first_p = parsed.first().unwrap().0;
				let last_p = parsed.last().unwrap().0;
				PageRange {
					since: (first_t != first_p).then_some(first_t),
					until: (last_t != last_p).then_some(last_t),
				}
			} else {
				PageRange {
					since: None,
					until: None,
				}
			};

			let out_ext = match ext {
				"txt" => "md",
				other => other,
			};
			let out_path = root.join(format!("out{range}.{out_ext}"));

			match ext {
				"txt" => join_markdown(&translated, &out_path)?,
				"fb2" => join_fb2(&translated, &out_path)?,
				_ => unreachable!(),
			}

			println!(
				"compiled {} chapters -> {}",
				translated.len(),
				out_path.display()
			);
		}
	}

	Ok(())
}
