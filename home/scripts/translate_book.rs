#!/usr/bin/env nix
---cargo
#! nix shell --impure --expr ``
#! nix let rust_flake = builtins.getFlake ''github:oxalica/rust-overlay'';
#! nix     nixpkgs_flake = builtins.getFlake ''nixpkgs'';
#! nix     pkgs = import nixpkgs_flake {
#! nix       system = builtins.currentSystem;
#! nix       overlays = [rust_flake.overlays.default];
#! nix     };
#! nix     toolchain = pkgs.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default.override {
#! nix       extensions = ["rust-src"];
#! nix     });
#! nix
#! nix in toolchain
#! nix ``
#! nix --command sh -c ``cargo -Zscript $0``

[dependencies]
clap = { version = "4", features = ["derive"] }
regex = "1"
eyre = "0.6"
walkdir = "2"
tokio = { version = "1", features = ["rt-multi-thread","macros","process","fs","io-util","time"] }
quick-xml = "0.36"
---

use clap::Parser;
use eyre::{Result, eyre};
use quick_xml::events::Event;
use quick_xml::Reader;
use regex::Regex;
use std::{fs, io::{BufRead, BufReader, Write}, path::{Path, PathBuf}, process::Stdio};
use tokio::{process::Command, sync::Semaphore};
use walkdir::WalkDir;

#[derive(Parser, Debug)]
struct Args {
    #[arg(short, long)]
    wlimit: String,
    /// Chapter pattern (only used for .txt files)
    #[arg(long)]
    chapter_pattern: Option<String>,
    #[arg(long, default_value_t = 2)]
    max_jobs: usize,
    /// Directory to unpack chapters into (defaults to current directory)
    #[arg(short, long, default_value = ".")]
    unpack_dir: PathBuf,
}

#[tokio::main(flavor = "multi_thread")]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Create unpack directory if it doesn't exist (without -p flag, so parent must exist)
    if !args.unpack_dir.exists() {
        fs::create_dir(&args.unpack_dir)?;
    }

    let chapters_split = args.unpack_dir.join("chapters_split");
    let chapters_de = args.unpack_dir.join("chapters_de");
    let chapters_ti = args.unpack_dir.join("chapters_ti");
    let failed_book_parser = args.unpack_dir.join("failed_book_parser");
    let failed_translate = args.unpack_dir.join("failed_translate");

    fs::create_dir_all(&chapters_split).unwrap();
    fs::create_dir_all(&chapters_de).unwrap();
    fs::create_dir_all(&chapters_ti).unwrap();
    fs::create_dir_all(&failed_book_parser).unwrap();
    fs::create_dir_all(&failed_translate).unwrap();

    // Find input book file
    let input = find_first_book(".").ok_or_else(|| eyre!("no .txt or .fb2 file found"))?;

    // Get file extension and validate
    let ext = input.extension()
        .and_then(|e| e.to_str())
        .ok_or_else(|| eyre!("input file has no extension"))?;

    // Validate chapter_pattern usage and split chapters based on file type
    match ext {
        "txt" => {
            let chapter_pattern = args.chapter_pattern.as_ref()
                .map(|s| s.as_str())
                .unwrap_or(r"^Глава [0-9]+");
            let chapter_re = Regex::new(chapter_pattern)?;
            split_into_chapters(&input, &chapter_re, &chapters_split)?;
        }
        "fb2" => {
            if args.chapter_pattern.is_some() {
                eprintln!("Error: --chapter-pattern is not applicable to .fb2 files");
                std::process::exit(1);
            }
            split_fb2_into_chapters(&input, &chapters_split)?;
        }
        _ => {
            eprintln!("Error: unsupported file extension '.{}'. Only .txt and .fb2 are supported.", ext);
            std::process::exit(1);
        }
    }

    let mut chapters = collect_numbered(&chapters_split.to_string_lossy(), "chapter_", ".txt")?;
    chapters.sort_by_key(|(n, _)| *n);

    let sem = Semaphore::new(args.max_jobs);
    {
        let mut tasks = Vec::new();
        for (num, path) in &chapters {
            let num = *num;
            let path = path.clone();
            let chapters_de = chapters_de.clone();
            let permit = sem.clone().acquire_owned().await.unwrap();
            tasks.push(tokio::spawn(async move {
                let _p = permit;
                run_book_parser(&path, num, &chapters_de).await
            }));
        }
        for t in tasks { t.await.unwrap()?; }
    }

    let mut des = collect_numbered(&chapters_de.to_string_lossy(), "chapter_", ".txt")?;
    des.sort_by_key(|(n, _)| *n);
    {
        let mut tasks = Vec::new();
        for (num, _) in &des {
            let num = *num;
            let wlimit = args.wlimit.clone();
            let chapters_de = chapters_de.clone();
            let chapters_ti = chapters_ti.clone();
            let permit = sem.clone().acquire_owned().await.unwrap();
            tasks.push(tokio::spawn(async move {
                let _p = permit;
                run_translate(num, &wlimit, &chapters_de, &chapters_ti).await
            }));
        }
        for t in tasks { t.await.unwrap()?; }
    }

    {
        let fails = glob_simple(&failed_book_parser.to_string_lossy(), ".fail")?;
        if !fails.is_empty() {
            let mut tasks = Vec::new();
            for fail in fails {
                let num: u32 = fs::read_to_string(&fail).unwrap().trim().parse().unwrap();
                let _ = fs::remove_file(chapters_de.join(format!("chapter_{num}.txt")));
                let _ = fs::remove_file(chapters_ti.join(format!("chapter_{num}.txt")));
                let ch = chapters_split.join(format!("chapter_{num}.txt"));
                let chapters_de = chapters_de.clone();
                let permit = sem.clone().acquire_owned().await.unwrap();
                tasks.push(tokio::spawn(async move {
                    let _p = permit;
                    run_book_parser(&ch, num, &chapters_de).await
                }));
            }
            for t in tasks { t.await.unwrap()?; }
        }
    }

    {
        let fails = glob_simple(&failed_translate.to_string_lossy(), ".fail")?;
        if !fails.is_empty() {
            let mut tasks = Vec::new();
            for fail in fails {
                let num: u32 = fs::read_to_string(&fail).unwrap().trim().parse().unwrap();
                let _ = fs::remove_file(chapters_ti.join(format!("chapter_{num}.txt")));
                let wlimit = args.wlimit.clone();
                let chapters_de = chapters_de.clone();
                let chapters_ti = chapters_ti.clone();
                let permit = sem.clone().acquire_owned().await.unwrap();
                tasks.push(tokio::spawn(async move {
                    let _p = permit;
                    run_translate(num, &wlimit, &chapters_de, &chapters_ti).await
                }));
            }
            for t in tasks { t.await.unwrap()?; }
        }
    }

    let out_path = args.unpack_dir.join("out.txt");
    join_chapters_markdown(&chapters_ti.to_string_lossy(), &out_path.to_string_lossy())?;
    Ok(())
}

fn find_first_book(root: &str) -> Option<PathBuf> {
    for e in WalkDir::new(root).into_iter().filter_map(|e| e.ok()) {
        let p = e.path();
        if p.is_file() {
            if let Some(ext) = p.extension() {
                if ext == "txt" || ext == "fb2" {
                    return Some(p.to_path_buf());
                }
            }
        }
    }
    None
}

fn split_into_chapters(input: &Path, chapter_re: &Regex, outdir: &Path) -> Result<()> {
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

fn split_fb2_into_chapters(input: &Path, outdir: &Path) -> Result<()> {
    let content = fs::read_to_string(input)?;
    let mut reader = Reader::from_str(&content);
    reader.config_mut().trim_text(true);

    let num_re = Regex::new(r"[0-9]+").unwrap();
    let mut buf = Vec::new();
    let mut in_body = false;
    let mut section_depth = 0;
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
                } else if in_section && name.as_ref() == b"p" {
                    // Start of paragraph
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
                    // End of paragraph - add newline
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
                        // Try to extract chapter number from title
                        if let Some(m) = num_re.find(&text) {
                            let num: u32 = text[m.start()..m.end()].parse().unwrap();
                            let file = fs::File::create(outdir.join(format!("chapter_{num}.txt")))?;
                            current_chapter = Some((num, file));
                        }
                    } else if current_chapter.is_some() {
                        current_text.push_str(&text);
                    }
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(eyre!("Error parsing FB2 at position {}: {:?}", reader.buffer_position(), e)),
            _ => {}
        }
        buf.clear();
    }

    Ok(())
}

async fn run_book_parser(ch: &Path, num: u32, chapters_de: &Path) -> Result<()> {
    let de = chapters_de.join(format!("chapter_{num}.txt"));
    let status = Command::new("sh")
        .arg("-c")
        .arg(format!("book_parser -l German -f '{}' > '{}'", ch.display(), de.display()))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await?;
    if !status.success() {
        let failed_dir = chapters_de.parent().unwrap().join("failed_book_parser");
        fs::write(failed_dir.join(format!("chapter_{num}.fail")), format!("{num}\n")).unwrap();
        return Err(eyre!("book_parser failed for chapter {num}"));
    }
    Ok(())
}

async fn run_translate(num: u32, wlimit: &str, chapters_de: &Path, chapters_ti: &Path) -> Result<()> {
    let de = chapters_de.join(format!("chapter_{num}.txt"));
    let ti = chapters_ti.join(format!("chapter_{num}.txt"));
    let cmd = format!("translate_infrequent -l de -w {} < '{}' > '{}'", shell_escape(wlimit), de.display(), ti.display());
    let status = Command::new("sh")
        .arg("-c")
        .arg(cmd)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await?;
    if !status.success() {
        let failed_dir = chapters_de.parent().unwrap().join("failed_translate");
        fs::write(failed_dir.join(format!("chapter_{num}.fail")), format!("{num}\n")).unwrap();
        return Err(eyre!("translate_infrequent failed for chapter {num}"));
    }
    Ok(())
}

fn collect_numbered(dir: &str, prefix: &str, suffix: &str) -> Result<Vec<(u32, PathBuf)>> {
    let mut v = Vec::new();
    for e in fs::read_dir(dir)? {
        let e = e?;
        let p = e.path();
        if !p.is_file() { continue; }
        let name = e.file_name().to_string_lossy().to_string();
        if name.starts_with(prefix) && name.ends_with(suffix) {
            if let Some(num) = extract_number(&name) {
                v.push((num, p));
            }
        }
    }
    Ok(v)
}

fn extract_number(s: &str) -> Option<u32> {
    let re = Regex::new(r"([0-9]+)").unwrap();
    re.captures(s).and_then(|c| c.get(1)).and_then(|m| m.as_str().parse::<u32>().ok())
}

fn glob_simple(dir: &str, ext: &str) -> Result<Vec<PathBuf>> {
    let mut v = Vec::new();
    for e in fs::read_dir(dir)? {
        let e = e?;
        let p = e.path();
        if p.is_file() && p.extension().map(|x| format!(".{}", x.to_string_lossy()) == ext).unwrap_or(false) {
            v.push(p);
        }
    }
    Ok(v)
}

fn join_chapters_markdown(dir: &str, out: &str) -> Result<()> {
    let mut parts = collect_numbered(dir, "chapter_", ".txt")?;
    parts.sort_by_key(|(n, _)| *n);
    let mut out_f = fs::File::create(out)?;
    let mut first = true;
    for (num, path) in parts {
        if !first {
            out_f.write_all(b"\n\n")?;
        } else {
            first = false;
        }
        writeln!(out_f, "# Глава {}", num)?;
        let mut f = BufReader::new(fs::File::open(path)?);
        let mut buf = Vec::new();
        f.read_to_end(&mut buf)?;
        out_f.write_all(&buf)?;
    }
    Ok(())
}

fn shell_escape(s: &str) -> String {
    if s.bytes().all(|b| b.is_ascii_alphanumeric()) { return s.to_string(); }
    format!("'{}'", s.replace('\'', r"'\''"))
}
