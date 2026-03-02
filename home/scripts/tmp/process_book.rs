#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4", features = ["derive"] }
regex = "1"
eyre = "0.6"
tokio = { version = "1", features = ["rt-multi-thread","macros","process","fs","io-util","time"] }
futures = "0.3"
quick-xml = "0.36"
zip = "2"
dirs = "5"
---

use clap::{Args, Parser, Subcommand, ValueEnum};
use eyre::{Result, eyre};
use quick_xml::Reader;
use quick_xml::events::Event;
use regex::Regex;
use std::io::{BufRead, BufReader, Read, Write as _};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::OnceLock;
use std::{fmt, fs};
use tokio::process::Command;
use zip::ZipWriter;
use zip::write::FileOptions;

#[derive(Parser)]
struct Cli {
    /// Base directory for all books
    #[arg(long, default_value_os_t = default_dir())]
    dir: PathBuf,
    /// Max parallel jobs for translate
    #[arg(long, default_value_t = 2)]
    max_jobs: usize,
    /// Overwrite existing files instead of skipping
    #[arg(long)]
    force: bool,
    #[command(subcommand)]
    cmd: Cmd,
}

fn default_dir() -> PathBuf {
    dirs::home_dir()
        .expect("no home directory")
        .join("tmp/process_book")
}

#[derive(Args, Clone)]
struct ChapterPatternArgs {
    /// Chapter heading pattern regex (for .txt files and web pages)
    #[arg(long)]
    chapter_pattern: Option<String>,
}

#[derive(Subcommand)]
enum Cmd {
    /// Split a local book file into sections (stored as .md)
    FromFile {
        /// Input book file (.txt, .fb2, or .epub)
        #[arg(short, long)]
        file: PathBuf,
        #[command(flatten)]
        pattern: ChapterPatternArgs,
    },
    /// Load book pages from a URL
    ///
    /// URL format: https://site.com/b/12345/read#t1..100
    /// The trailing range (Rust-like, inclusive with ..=) specifies pages.
    Load {
        /// URL with trailing range, e.g. https://example.com/b/123/read#t1..50
        url: String,
        /// CSS selectors for book_parser (can be repeated)
        #[arg(short, long)]
        css: Vec<String>,
        /// Parallel page downloads per chunk
        #[arg(long, default_value_t = 16)]
        parallel: usize,
        /// Seconds to wait between chunks (default: 0)
        #[arg(long, default_value_t = 0)]
        timeout: u64,
        #[command(flatten)]
        pattern: ChapterPatternArgs,
    },
    /// Run book_parser + translate_infrequent on sections
    Translate {
        /// Book name (directory under --dir)
        name: String,
        #[arg(short, long)]
        wlimit: String,
        /// Target language (passed to book_parser -l and translate_infrequent -l)
        #[arg(short, long)]
        language: String,
        /// Section range, e.g. 1..50, 1..=50, 5.., ..=20
        #[arg(short, long)]
        range: Option<String>,
    },
    /// Assemble translated sections into a book
    Compile {
        /// Book name (directory under --dir)
        name: String,
        /// Output format
        #[arg(short, long, default_value = "epub")]
        format: OutputFormat,
    },
}

#[derive(Clone, ValueEnum)]
enum OutputFormat {
    Epub,
    Md,
    Markdown,
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

fn parse_range(s: &str) -> Result<PageRange> {
    let re = Regex::new(r"^(\d+)?\.\.(=?)(\d+)?$").unwrap();
    let caps = re
        .captures(s)
        .ok_or_else(|| eyre!("invalid range '{s}', expected e.g. 1..50, 1..=50, 5.., ..=20"))?;
    let since = caps.get(1).map(|m| m.as_str().parse::<u32>()).transpose()?;
    let inclusive = &caps[2] == "=";
    let end_raw = caps.get(3).map(|m| m.as_str().parse::<u32>()).transpose()?;
    let until = match (inclusive, end_raw) {
        (true, Some(n)) => Some(n),
        (false, Some(0)) => return Err(eyre!("empty range: {s}")),
        (false, Some(n)) => Some(n - 1),
        (_, None) => None,
    };
    if let (Some(s), Some(u)) = (since, until) {
        if u < s {
            return Err(eyre!("empty range: {s}"));
        }
    }
    Ok(PageRange { since, until })
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

fn book_root(base: &Path, name: &str) -> &'static PathBuf {
    static ROOT: OnceLock<PathBuf> = OnceLock::new();
    ROOT.get_or_init(|| base.join(name))
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

// --- markdown section format ---

fn paragraphs_to_md(title: Option<&str>, paragraphs: &[&str]) -> String {
    let mut s = String::new();
    if let Some(t) = title {
        s.push_str("# ");
        s.push_str(t);
        s.push('\n');
    }
    for p in paragraphs {
        let trimmed = p.trim();
        if !trimmed.is_empty() {
            s.push('\n');
            s.push_str(trimmed);
            s.push('\n');
        }
    }
    s
}

fn md_title(md: &str) -> Option<String> {
    for line in md.lines() {
        if let Some(title) = line.strip_prefix("# ") {
            let t = title.trim();
            if !t.is_empty() {
                return Some(t.to_string());
            }
        }
    }
    None
}

fn md_to_plaintext(md: &str) -> String {
    let mut out = String::new();
    for line in md.lines() {
        if line.starts_with("# ") || line.trim().is_empty() {
            continue;
        }
        out.push_str(line);
        out.push('\n');
    }
    out
}

/// Decode common HTML/XML entities to plain text
fn decode_entities(s: &str) -> String {
    s.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
}

// --- parsing: all formats -> section_N.md ---

fn parse_txt(input: &Path, chapter_re: &Regex, outdir: &Path) -> Result<u32> {
    let f = fs::File::open(input)?;
    let r = BufReader::new(f);
    let num_re = Regex::new(r"[0-9]+").unwrap();
    let mut current_title: Option<String> = None;
    let mut current_lines: Vec<String> = Vec::new();
    let mut current_num: Option<u32> = None;
    let mut count = 0u32;

    let flush = |num: u32, title: Option<&str>, lines: &[String], outdir: &Path| -> Result<()> {
        let refs: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
        let md = paragraphs_to_md(title, &refs);
        fs::write(outdir.join(format!("section_{num}.md")), md)?;
        Ok(())
    };

    for line in r.lines() {
        let line = line?;
        if chapter_re.is_match(&line) {
            if let Some(m) = num_re.find(&line) {
                if let Some(num) = current_num {
                    flush(num, current_title.as_deref(), &current_lines, outdir)?;
                    count += 1;
                }
                let num: u32 = line[m.start()..m.end()].parse().unwrap();
                current_num = Some(num);
                current_title = Some(line.clone());
                current_lines.clear();
                continue;
            }
        }
        if current_num.is_some() {
            current_lines.push(line);
        }
    }
    if let Some(num) = current_num {
        flush(num, current_title.as_deref(), &current_lines, outdir)?;
        count += 1;
    }
    Ok(count)
}

fn parse_fb2(input: &Path, outdir: &Path) -> Result<u32> {
    let content = fs::read_to_string(input)?;
    let mut reader = Reader::from_str(&content);
    reader.config_mut().trim_text(true);

    let num_re = Regex::new(r"[0-9]+").unwrap();
    let mut buf = Vec::new();
    let mut in_body = false;
    let mut section_depth: u32 = 0;
    let mut in_section = false;
    let mut in_title = false;
    let mut title_text = String::new();
    let mut current_num: Option<u32> = None;
    let mut paragraphs: Vec<String> = Vec::new();
    let mut current_para = String::new();
    let mut count = 0u32;

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
                        title_text.clear();
                        paragraphs.clear();
                        current_num = None;
                    }
                } else if in_section && name.as_ref() == b"title" {
                    in_title = true;
                    title_text.clear();
                }
            }
            Ok(Event::End(e)) => {
                let name = e.name();
                if name.as_ref() == b"body" {
                    in_body = false;
                } else if name.as_ref() == b"section" {
                    if section_depth == 1 {
                        if let Some(num) = current_num {
                            let refs: Vec<&str> = paragraphs.iter().map(|s| s.as_str()).collect();
                            let title = if title_text.is_empty() {
                                None
                            } else {
                                Some(title_text.as_str())
                            };
                            let md = paragraphs_to_md(title, &refs);
                            fs::write(outdir.join(format!("section_{num}.md")), md)?;
                            count += 1;
                        }
                        in_section = false;
                    }
                    section_depth = section_depth.saturating_sub(1);
                } else if name.as_ref() == b"title" {
                    in_title = false;
                    if current_num.is_none() {
                        if let Some(m) = num_re.find(&title_text) {
                            current_num = Some(title_text[m.start()..m.end()].parse().unwrap());
                        }
                    }
                } else if in_section && name.as_ref() == b"p" && !in_title {
                    if !current_para.is_empty() {
                        paragraphs.push(std::mem::take(&mut current_para));
                    }
                }
            }
            Ok(Event::Text(e)) => {
                if in_section {
                    let text = e.unescape().unwrap_or_default();
                    if in_title {
                        title_text.push_str(&text);
                    } else if current_num.is_some() {
                        current_para.push_str(&text);
                    }
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => {
                return Err(eyre!(
                    "FB2 parse error at {}: {e:?}",
                    reader.buffer_position()
                ));
            }
            _ => {}
        }
        buf.clear();
    }
    Ok(count)
}

fn parse_epub(input: &Path, outdir: &Path) -> Result<u32> {
    let file = fs::File::open(input)?;
    let mut archive = zip::ZipArchive::new(BufReader::new(file))?;

    let opf_path = find_opf_path(&mut archive)?;
    let spine_hrefs = read_spine(&mut archive, &opf_path)?;

    let opf_dir = Path::new(&opf_path)
        .parent()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default();

    let mut count = 0u32;
    for href in &spine_hrefs {
        let full_path = if opf_dir.is_empty() {
            href.clone()
        } else {
            format!("{opf_dir}/{href}")
        };

        let mut entry = match archive.by_name(&full_path) {
            Ok(e) => e,
            Err(_) => continue,
        };
        let mut content = String::new();
        entry.read_to_string(&mut content)?;

        let paras = extract_paragraphs_from_xhtml(&content);
        if paras.is_empty() {
            continue;
        }

        count += 1;
        let title = extract_title_from_xhtml(&content);
        let refs: Vec<&str> = paras.iter().map(|s| s.as_str()).collect();
        let md = paragraphs_to_md(title.as_deref(), &refs);
        fs::write(outdir.join(format!("section_{count}.md")), md)?;
    }
    Ok(count)
}

fn find_opf_path(archive: &mut zip::ZipArchive<BufReader<fs::File>>) -> Result<String> {
    let mut container = archive.by_name("META-INF/container.xml")?;
    let mut content = String::new();
    container.read_to_string(&mut content)?;

    let re = Regex::new(r#"full-path="([^"]+\.opf)""#).unwrap();
    re.captures(&content)
        .and_then(|c| c.get(1))
        .map(|m| m.as_str().to_string())
        .ok_or_else(|| eyre!("no .opf path in container.xml"))
}

fn read_spine(
    archive: &mut zip::ZipArchive<BufReader<fs::File>>,
    opf_path: &str,
) -> Result<Vec<String>> {
    let mut opf_entry = archive.by_name(opf_path)?;
    let mut opf = String::new();
    opf_entry.read_to_string(&mut opf)?;

    let item_re = Regex::new(r#"<item\s[^>]*id="([^"]+)"[^>]*href="([^"]+)"[^>]*/?"#).unwrap();
    let mut manifest = std::collections::HashMap::new();
    for cap in item_re.captures_iter(&opf) {
        manifest.insert(cap[1].to_string(), cap[2].to_string());
    }

    let itemref_re = Regex::new(r#"<itemref\s[^>]*idref="([^"]+)""#).unwrap();
    let mut hrefs = Vec::new();
    for cap in itemref_re.captures_iter(&opf) {
        if let Some(href) = manifest.get(&cap[1]) {
            hrefs.push(href.clone());
        }
    }
    Ok(hrefs)
}

fn extract_paragraphs_from_xhtml(xhtml: &str) -> Vec<String> {
    let mut reader = Reader::from_str(xhtml);
    reader.config_mut().trim_text(true);
    let mut buf = Vec::new();
    let mut paras = Vec::new();
    let mut in_p = false;
    let mut current = String::new();
    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(e)) if e.name().as_ref() == b"p" => {
                in_p = true;
                current.clear();
            }
            Ok(Event::End(e)) if e.name().as_ref() == b"p" => {
                in_p = false;
                let trimmed = current.trim().to_string();
                if !trimmed.is_empty() {
                    paras.push(trimmed);
                }
            }
            Ok(Event::Text(e)) if in_p => {
                current.push_str(&e.unescape().unwrap_or_default());
            }
            Ok(Event::Eof) => break,
            Err(_) => break,
            _ => {}
        }
        buf.clear();
    }
    paras
}

fn extract_title_from_xhtml(xhtml: &str) -> Option<String> {
    let mut reader = Reader::from_str(xhtml);
    reader.config_mut().trim_text(true);
    let mut buf = Vec::new();
    let mut in_h = false;
    let mut title = String::new();
    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(e)) => {
                let n = e.name();
                if matches!(n.as_ref(), b"h1" | b"h2" | b"h3") {
                    in_h = true;
                    title.clear();
                }
            }
            Ok(Event::End(e)) => {
                let n = e.name();
                if matches!(n.as_ref(), b"h1" | b"h2" | b"h3") && in_h {
                    let t = title.trim().to_string();
                    if !t.is_empty() {
                        return Some(t);
                    }
                    in_h = false;
                }
            }
            Ok(Event::Text(e)) if in_h => {
                title.push_str(&e.unescape().unwrap_or_default());
            }
            Ok(Event::Eof) => return None,
            Err(_) => return None,
            _ => {}
        }
        buf.clear();
    }
}

// --- contiguity enforcement ---

/// Find the first gap in `start..=end` where `section_N.md` is missing.
/// Remove all section files at and after the gap. Returns the gap page, if any.
fn enforce_contiguous(dir: &Path, start: u32, end: u32) -> Option<u32> {
    let mut gap = None;
    for page in start..=end {
        let path = dir.join(format!("section_{page}.md"));
        if gap.is_some() {
            let _ = fs::remove_file(path);
        } else if !path.exists() {
            gap = Some(page);
        }
    }
    gap
}

// --- load from web ---

/// Parse URL with a range at the end like `https://site.com/chapter/1..50/`
/// Trailing `/` is allowed after the range.
/// Returns (url_template_with_{}, start, end_inclusive)
fn parse_load_url(url: &str) -> Result<(String, u32, u32)> {
    let range_re = Regex::new(r"(\d+)\.\.(=?)(\d+)/?$").unwrap();
    let caps = range_re
        .captures(url)
        .ok_or_else(|| eyre!("URL must end with a range like 1..100 or 1..=100 (trailing / ok)"))?;

    let start: u32 = caps[1].parse()?;
    let inclusive = &caps[2] == "=";
    let end_raw: u32 = caps[3].parse()?;
    let end = if inclusive { end_raw } else { end_raw - 1 };

    if end < start {
        return Err(eyre!("empty range: {start}..{end_raw}"));
    }

    let m = caps.get(0).unwrap();
    let suffix = &url[m.end()..]; // empty or already consumed by regex
    let base = format!("{}{{}}{suffix}", &url[..caps.get(1).unwrap().start()]);

    Ok((base, start, end))
}

/// Derive a book name from the URL for the directory name
fn book_name_from_url(url: &str) -> String {
    // strip trailing range (with optional /)
    let range_re = Regex::new(r"\d+\.\.=?\d+/?$").unwrap();
    let stripped = range_re.replace(url, "");
    // strip scheme
    let stripped = stripped
        .strip_prefix("https://")
        .or_else(|| stripped.strip_prefix("http://"))
        .unwrap_or(&stripped);
    // strip fragment and query
    let stripped = stripped.split('#').next().unwrap_or(stripped);
    let stripped = stripped.split('?').next().unwrap_or(stripped);
    let parts: Vec<&str> = stripped
        .split('/')
        .skip(1) // domain
        .filter(|s| !s.is_empty())
        .collect();
    if parts.is_empty() {
        return "book".to_string();
    }
    parts.join("_")
}

async fn load_page(
    url_template: &str,
    page: u32,
    css_selectors: &[String],
    outdir: &Path,
) -> Result<()> {
    let url = url_template.replace("{}", &page.to_string());
    let out_path = outdir.join(format!("section_{page}.md"));

    let mut cmd_args = vec!["book_parser".to_string(), "--url".to_string(), url];
    for sel in css_selectors {
        cmd_args.push("-c".to_string());
        cmd_args.push(sel.clone());
    }

    let output = Command::new(&cmd_args[0])
        .args(&cmd_args[1..])
        .output()
        .await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(eyre!(
            "book_parser failed for page {page}: {}",
            stderr.trim()
        ));
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let decoded = decode_entities(&text);
    let lines: Vec<&str> = decoded.lines().collect();
    let md = paragraphs_to_md(None, &lines);
    fs::write(out_path, md)?;
    println!("  page {page} ok");

    Ok(())
}

// --- translation ---

async fn run_book_parser(
    section: &Path,
    num: u32,
    language: &str,
    de_dir: &Path,
    fail_dir: &Path,
) -> Result<()> {
    let md = fs::read_to_string(section)?;
    let plaintext = md_to_plaintext(&md);
    let tmp = de_dir.join(format!("section_{num}.tmp.txt"));
    fs::write(&tmp, &plaintext)?;

    let de_txt = de_dir.join(format!("section_{num}.txt"));
    let status = Command::new("sh")
        .arg("-c")
        .arg(format!(
            "book_parser -l {} -f '{}' > '{}'",
            shell_escape(language),
            tmp.display(),
            de_txt.display()
        ))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await?;
    let _ = fs::remove_file(&tmp);

    if !status.success() {
        fs::write(
            fail_dir.join(format!("section_{num}.fail")),
            format!("{num}\n"),
        )?;
        return Err(eyre!("book_parser failed for section {num}"));
    }

    let translated = fs::read_to_string(&de_txt)?;
    let title = md_title(&md);
    let lines: Vec<&str> = translated.lines().collect();
    let out_md = paragraphs_to_md(title.as_deref(), &lines);
    fs::write(de_dir.join(format!("section_{num}.md")), out_md)?;
    let _ = fs::remove_file(&de_txt);

    Ok(())
}

async fn run_translate_infrequent(
    num: u32,
    language: &str,
    wlimit: &str,
    de_dir: &Path,
    ti_dir: &Path,
    fail_dir: &Path,
) -> Result<()> {
    let de = de_dir.join(format!("section_{num}.md"));
    let md = fs::read_to_string(&de)?;
    let plaintext = md_to_plaintext(&md);
    let tmp_in = ti_dir.join(format!("section_{num}.tmp.txt"));
    fs::write(&tmp_in, &plaintext)?;

    let tmp_out = ti_dir.join(format!("section_{num}.txt"));
    let cmd = format!(
        "translate_infrequent -l {} -w {} < '{}' > '{}'",
        shell_escape(language),
        shell_escape(wlimit),
        tmp_in.display(),
        tmp_out.display()
    );
    let status = Command::new("sh")
        .arg("-c")
        .arg(cmd)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await?;
    let _ = fs::remove_file(&tmp_in);

    if !status.success() {
        fs::write(
            fail_dir.join(format!("section_{num}.fail")),
            format!("{num}\n"),
        )?;
        return Err(eyre!("translate_infrequent failed for section {num}"));
    }

    let translated = fs::read_to_string(&tmp_out)?;
    let title = md_title(&md);
    let lines: Vec<&str> = translated.lines().collect();
    let out_md = paragraphs_to_md(title.as_deref(), &lines);
    fs::write(ti_dir.join(format!("section_{num}.md")), out_md)?;
    let _ = fs::remove_file(&tmp_out);

    Ok(())
}

fn shell_escape(s: &str) -> String {
    if s.bytes().all(|b| b.is_ascii_alphanumeric()) {
        return s.to_string();
    }
    format!("'{}'", s.replace('\'', r"'\''"))
}

// --- compile ---

fn compile_epub(sections: &[(u32, PathBuf)], out: &Path) -> Result<()> {
    let file = fs::File::create(out)?;
    let mut zip = ZipWriter::new(file);

    let opts_stored: FileOptions<'_, ()> =
        FileOptions::default().compression_method(zip::CompressionMethod::Stored);
    let opts: FileOptions<'_, ()> =
        FileOptions::default().compression_method(zip::CompressionMethod::Deflated);

    zip.start_file("mimetype", opts_stored)?;
    zip.write_all(b"application/epub+zip")?;

    zip.start_file("META-INF/container.xml", opts.clone())?;
    zip.write_all(
        b"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n\
		  <container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\n\
		  <rootfiles>\n\
		  <rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/>\n\
		  </rootfiles>\n\
		  </container>\n",
    )?;

    for (num, path) in sections {
        let md = fs::read_to_string(path)?;
        let xhtml = md_to_xhtml(&md, *num);
        zip.start_file(format!("OEBPS/section_{num}.xhtml"), opts.clone())?;
        zip.write_all(xhtml.as_bytes())?;
    }

    let mut opf = String::from(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n\
		 <package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"uid\">\n\
		 <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n\
		 <dc:identifier id=\"uid\">process-book-output</dc:identifier>\n\
		 <dc:title>Translated Book</dc:title>\n\
		 <dc:language>de</dc:language>\n\
		 <meta property=\"dcterms:modified\">2025-01-01T00:00:00Z</meta>\n\
		 </metadata>\n\
		 <manifest>\n\
		 <item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n",
    );
    for (num, _) in sections {
        opf.push_str(&format!(
			"<item id=\"s{num}\" href=\"section_{num}.xhtml\" media-type=\"application/xhtml+xml\"/>\n"
		));
    }
    opf.push_str("</manifest>\n<spine>\n");
    for (num, _) in sections {
        opf.push_str(&format!("<itemref idref=\"s{num}\"/>\n"));
    }
    opf.push_str("</spine>\n</package>\n");

    zip.start_file("OEBPS/content.opf", opts.clone())?;
    zip.write_all(opf.as_bytes())?;

    let mut nav = String::from(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n\
		 <html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\">\n\
		 <head><title>Navigation</title></head>\n\
		 <body>\n\
		 <nav epub:type=\"toc\">\n\
		 <ol>\n",
    );
    for (num, path) in sections {
        let md = fs::read_to_string(path)?;
        let title = md_title(&md).unwrap_or_else(|| format!("Page {num}"));
        nav.push_str(&format!(
            "<li><a href=\"section_{num}.xhtml\">{}</a></li>\n",
            escape_xml(&title)
        ));
    }
    nav.push_str("</ol>\n</nav>\n</body>\n</html>\n");

    zip.start_file("OEBPS/nav.xhtml", opts)?;
    zip.write_all(nav.as_bytes())?;

    zip.finish()?;
    Ok(())
}

fn compile_markdown(sections: &[(u32, PathBuf)], out: &Path) -> Result<()> {
    let mut f = fs::File::create(out)?;
    for (i, (num, path)) in sections.iter().enumerate() {
        if i > 0 {
            f.write_all(b"\n")?;
        }
        let md = fs::read_to_string(path)?;
        if md_title(&md).is_none() {
            writeln!(f, "## Page {num}\n")?;
        }
        f.write_all(md.as_bytes())?;
    }
    Ok(())
}

fn escape_xml(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

fn md_to_xhtml(md: &str, page_num: u32) -> String {
    let mut s = String::from(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n\
		 <html xmlns=\"http://www.w3.org/1999/xhtml\">\n\
		 <head><title></title></head>\n\
		 <body>\n",
    );
    if md_title(md).is_none() {
        s.push_str(&format!("<h2>Page {page_num}</h2>\n"));
    }
    for line in md.lines() {
        if let Some(title) = line.strip_prefix("# ") {
            let t = title.trim();
            if !t.is_empty() {
                s.push_str(&format!("<h1>{}</h1>\n", escape_xml(t)));
            }
        } else if !line.trim().is_empty() {
            s.push_str(&format!("<p>{}</p>\n", escape_xml(line)));
        }
    }
    s.push_str("</body>\n</html>\n");
    s
}

#[tokio::main(flavor = "multi_thread")]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.cmd {
        Cmd::FromFile { file, pattern } => {
            if !file.exists() {
                return Err(eyre!("file '{}' does not exist", file.display()));
            }
            let ext = file
                .extension()
                .and_then(|e| e.to_str())
                .ok_or_else(|| eyre!("input file has no extension"))?;
            match ext {
                "txt" | "fb2" | "epub" => {}
                _ => {
                    return Err(eyre!(
                        "unsupported extension '.{ext}', expected .txt, .fb2, or .epub"
                    ));
                }
            }
            let stem = file
                .file_stem()
                .ok_or_else(|| eyre!("input file has no stem"))?
                .to_string_lossy()
                .to_string();

            let root = book_root(&cli.dir, &stem);
            let sections_dir = root.join("sections");
            fs::create_dir_all(&sections_dir)?;

            let count = match ext {
                "txt" => {
                    let pat = pattern
                        .chapter_pattern
                        .as_deref()
                        .unwrap_or(r"^Глава [0-9]+");
                    let re = Regex::new(pat)?;
                    parse_txt(&file, &re, &sections_dir)?
                }
                "fb2" => {
                    if pattern.chapter_pattern.is_some() {
                        return Err(eyre!("--chapter-pattern is not applicable to .fb2 files"));
                    }
                    parse_fb2(&file, &sections_dir)?
                }
                "epub" => {
                    if pattern.chapter_pattern.is_some() {
                        return Err(eyre!("--chapter-pattern is not applicable to .epub files"));
                    }
                    parse_epub(&file, &sections_dir)?
                }
                _ => unreachable!(),
            };

            println!("parsed {count} sections -> {}", sections_dir.display());
        }

        Cmd::Load {
            url,
            css,
            parallel,
            timeout,
            pattern: _,
        } => {
            let (url_template, start, end) = parse_load_url(&url)?;
            let name = book_name_from_url(&url);
            let root = book_root(&cli.dir, &name);
            let sections_dir = root.join("sections");
            fs::create_dir_all(&sections_dir)?;

            if cli.force {
                println!("--force: will overwrite existing pages");
            } else {
                // enforce contiguity of any pre-existing sections
                if let Some(gap) = enforce_contiguous(&sections_dir, start, end) {
                    println!("cleaned post-gap sections (gap at {gap})");
                }
            }

            // collect pages to load
            let mut pages_to_load = Vec::new();
            let mut skipped = 0u32;
            for page in start..=end {
                let path = sections_dir.join(format!("section_{page}.md"));
                if path.exists() && !cli.force {
                    skipped += 1;
                    continue;
                }
                pages_to_load.push(page);
            }

            if skipped > 0 {
                eprintln!(
                    "warning: skipped {skipped} already-loaded pages (use --force to overwrite)"
                );
            }

            if pages_to_load.is_empty() {
                println!("all {} pages already loaded", end - start + 1);
                println!("book name: {name}");
                return Ok(());
            }

            let n_chunks = (pages_to_load.len() + parallel - 1) / parallel;
            println!(
                "loading {} pages in {} chunks of {} -> {}",
                pages_to_load.len(),
                n_chunks,
                parallel,
                sections_dir.display()
            );

            for (chunk_idx, chunk) in pages_to_load.chunks(parallel).enumerate() {
                if chunk_idx > 0 && timeout > 0 {
                    println!("  waiting {timeout}s between chunks...");
                    tokio::time::sleep(std::time::Duration::from_secs(timeout)).await;
                }

                let futs: Vec<_> = chunk
                    .iter()
                    .map(|&page| load_page(&url_template, page, &css, &sections_dir))
                    .collect();
                if let Err(e) = futures::future::try_join_all(futs).await {
                    enforce_contiguous(&sections_dir, start, end);
                    return Err(e);
                }
            }

            // enforce contiguity: nuke everything after first gap
            if let Some(gap) = enforce_contiguous(&sections_dir, start, end) {
                let loaded = gap - start;
                println!("loaded {loaded} contiguous pages ({start}..={})", gap - 1);
                return Err(eyre!("stopped at page {gap} (gap in sequence)"));
            }

            println!("loaded all {} pages ({start}..={end})", end - start + 1);
            println!("book name: {name}");
        }

        Cmd::Translate {
            name,
            wlimit,
            language,
            range,
        } => {
            let root = book_root(&cli.dir, &name);
            let sections_dir = root.join("sections");
            let de = root.join("sections_de");
            let ti = root.join("sections_ti");
            let fbp = root.join("failed_book_parser");
            let fti = root.join("failed_translate");

            if !sections_dir.exists() {
                return Err(eyre!(
                    "sections not found at '{}' — run `from-file` or `load` first",
                    sections_dir.display()
                ));
            }

            let range = match range {
                Some(s) => parse_range(&s)?,
                None => PageRange {
                    since: None,
                    until: None,
                },
            };
            fs::create_dir_all(&de)?;
            fs::create_dir_all(&ti)?;
            fs::create_dir_all(&fbp)?;
            fs::create_dir_all(&fti)?;

            let all = collect_numbered(&sections_dir, "section_", ".md")?;
            let sections: Vec<_> = all
                .into_iter()
                .filter(|(n, _)| range.contains(*n))
                .collect();

            println!(
                "translating {} sections{}",
                sections.len(),
                if range.since.is_some() || range.until.is_some() {
                    format!(" (range: {range})")
                } else {
                    String::new()
                }
            );

            // book_parser pass
            {
                let mut to_parse: Vec<(u32, PathBuf)> = Vec::new();
                let mut skipped = 0u32;
                for (num, path) in &sections {
                    if !cli.force && de.join(format!("section_{num}.md")).exists() {
                        skipped += 1;
                        continue;
                    }
                    to_parse.push((*num, path.clone()));
                }
                if skipped > 0 {
                    eprintln!(
                        "warning: skipped {skipped} already-parsed sections (use --force to overwrite)"
                    );
                }
                for chunk in to_parse.chunks(cli.max_jobs) {
                    let futs: Vec<_> = chunk
                        .iter()
                        .map(|(num, path)| run_book_parser(path, *num, &language, &de, &fbp))
                        .collect();
                    futures::future::try_join_all(futs).await?;
                }
            }

            // translate_infrequent pass
            {
                let mut to_translate: Vec<u32> = Vec::new();
                let mut skipped = 0u32;
                let des = collect_numbered(&de, "section_", ".md")?;
                for (num, _) in &des {
                    if !range.contains(*num) {
                        continue;
                    }
                    if !cli.force && ti.join(format!("section_{num}.md")).exists() {
                        skipped += 1;
                        continue;
                    }
                    to_translate.push(*num);
                }
                if skipped > 0 {
                    eprintln!(
                        "warning: skipped {skipped} already-translated sections (use --force to overwrite)"
                    );
                }
                for chunk in to_translate.chunks(cli.max_jobs) {
                    let futs: Vec<_> = chunk
                        .iter()
                        .map(|&num| run_translate_infrequent(num, &language, &wlimit, &de, &ti, &fti))
                        .collect();
                    futures::future::try_join_all(futs).await?;
                }
            }

            // retry book_parser failures
            {
                let fails = glob_fails(&fbp)?;
                let mut to_retry: Vec<(u32, PathBuf)> = Vec::new();
                for fail in fails {
                    let num: u32 = fs::read_to_string(&fail)?.trim().parse()?;
                    if !range.contains(num) {
                        continue;
                    }
                    let _ = fs::remove_file(de.join(format!("section_{num}.md")));
                    let _ = fs::remove_file(ti.join(format!("section_{num}.md")));
                    let _ = fs::remove_file(&fail);
                    to_retry.push((num, sections_dir.join(format!("section_{num}.md"))));
                }
                for chunk in to_retry.chunks(cli.max_jobs) {
                    let futs: Vec<_> = chunk
                        .iter()
                        .map(|(num, path)| run_book_parser(path, *num, &language, &de, &fbp))
                        .collect();
                    futures::future::try_join_all(futs).await?;
                }
            }

            // retry translate failures
            {
                let fails = glob_fails(&fti)?;
                let mut to_retry: Vec<u32> = Vec::new();
                for fail in fails {
                    let num: u32 = fs::read_to_string(&fail)?.trim().parse()?;
                    if !range.contains(num) {
                        continue;
                    }
                    let _ = fs::remove_file(ti.join(format!("section_{num}.md")));
                    let _ = fs::remove_file(&fail);
                    to_retry.push(num);
                }
                for chunk in to_retry.chunks(cli.max_jobs) {
                    let futs: Vec<_> = chunk
                        .iter()
                        .map(|&num| run_translate_infrequent(num, &language, &wlimit, &de, &ti, &fti))
                        .collect();
                    futures::future::try_join_all(futs).await?;
                }
            }

            println!("translation done");
        }

        Cmd::Compile { name, format } => {
            let root = book_root(&cli.dir, &name);
            let sections_dir = root.join("sections");
            let ti = root.join("sections_ti");

            let parsed = collect_numbered(&sections_dir, "section_", ".md")?;
            let translated = collect_numbered(&ti, "section_", ".md")?;

            if translated.is_empty() {
                return Err(eyre!("no translated sections found"));
            }

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

            let (out_ext, compile_fn): (&str, fn(&[(u32, PathBuf)], &Path) -> Result<()>) =
                match format {
                    OutputFormat::Epub => ("epub", compile_epub),
                    OutputFormat::Md | OutputFormat::Markdown => ("md", compile_markdown),
                };
            let out_path = root.join(format!("out{range}.{out_ext}"));

            if out_path.exists() && !cli.force {
                return Err(eyre!(
                    "output file '{}' already exists (use --force to overwrite)",
                    out_path.display()
                ));
            }

            compile_fn(&translated, &out_path)?;

            println!(
                "compiled {} sections -> {}",
                translated.len(),
                out_path.display()
            );
        }
    }

    Ok(())
}
