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
---

use clap::Parser;
use eyre::{Result, eyre};
use regex::Regex;
use std::{fs, io::{BufRead, BufReader, Write}, path::{Path, PathBuf}, process::Stdio};
use tokio::{process::Command, sync::Semaphore};
use walkdir::WalkDir;

#[derive(Parser, Debug)]
struct Args {
    #[arg(long = "wlimit")]
    wlimit: String,
    #[arg(long = "chapter-pattern", default_value = r"^Глава [0-9]+")]
    chapter_pattern: String,
    #[arg(long = "max-jobs", default_value_t = 2)]
    max_jobs: usize,
}

#[tokio::main(flavor = "multi_thread")]
async fn main() -> Result<()> {
    let args = Args::parse();
    let chapter_re = Regex::new(&args.chapter_pattern).unwrap();

    fs::create_dir_all("chapters_split").unwrap();
    fs::create_dir_all("chapters_de").unwrap();
    fs::create_dir_all("chapters_ti").unwrap();
    fs::create_dir_all("failed_book_parser").unwrap();
    fs::create_dir_all("failed_translate").unwrap();

    let input = find_first_txt(".").ok_or_else(|| eyre!("no .txt file found"))?;
    split_into_chapters(&input, &chapter_re, Path::new("chapters_split"))?;

    let mut chapters = collect_numbered("chapters_split", "chapter_", ".txt")?;
    chapters.sort_by_key(|(n, _)| *n);

    let sem = Semaphore::new(args.max_jobs);
    {
        let mut tasks = Vec::new();
        for (num, path) in &chapters {
            let num = *num;
            let path = path.clone();
            let permit = sem.clone().acquire_owned().await.unwrap();
            tasks.push(tokio::spawn(async move {
                let _p = permit;
                run_book_parser(&path, num).await
            }));
        }
        for t in tasks { t.await.unwrap()?; }
    }

    let mut des = collect_numbered("chapters_de", "chapter_", ".txt")?;
    des.sort_by_key(|(n, _)| *n);
    {
        let mut tasks = Vec::new();
        for (num, _) in &des {
            let num = *num;
            let wlimit = args.wlimit.clone();
            let permit = sem.clone().acquire_owned().await.unwrap();
            tasks.push(tokio::spawn(async move {
                let _p = permit;
                run_translate(num, &wlimit).await
            }));
        }
        for t in tasks { t.await.unwrap()?; }
    }

    {
        let fails = glob_simple("failed_book_parser", ".fail")?;
        if !fails.is_empty() {
            let mut tasks = Vec::new();
            for fail in fails {
                let num: u32 = fs::read_to_string(&fail).unwrap().trim().parse().unwrap();
                let _ = fs::remove_file(format!("chapters_de/chapter_{num}.txt"));
                let _ = fs::remove_file(format!("chapters_ti/chapter_{num}.txt"));
                let ch = format!("chapters_split/chapter_{num}.txt");
                let permit = sem.clone().acquire_owned().await.unwrap();
                tasks.push(tokio::spawn(async move {
                    let _p = permit;
                    run_book_parser(Path::new(&ch), num).await
                }));
            }
            for t in tasks { t.await.unwrap()?; }
        }
    }

    {
        let fails = glob_simple("failed_translate", ".fail")?;
        if !fails.is_empty() {
            let mut tasks = Vec::new();
            for fail in fails {
                let num: u32 = fs::read_to_string(&fail).unwrap().trim().parse().unwrap();
                let _ = fs::remove_file(format!("chapters_ti/chapter_{num}.txt"));
                let wlimit = args.wlimit.clone();
                let permit = sem.clone().acquire_owned().await.unwrap();
                tasks.push(tokio::spawn(async move {
                    let _p = permit;
                    run_translate(num, &wlimit).await
                }));
            }
            for t in tasks { t.await.unwrap()?; }
        }
    }

    join_chapters_markdown("chapters_ti", "out.txt")?;
    Ok(())
}

fn find_first_txt(root: &str) -> Option<PathBuf> {
    for e in WalkDir::new(root).into_iter().filter_map(|e| e.ok()) {
        let p = e.path();
        if p.is_file() && p.extension().map(|x| x == "txt").unwrap_or(false) {
            return Some(p.to_path_buf());
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

async fn run_book_parser(ch: &Path, num: u32) -> Result<()> {
    let de = format!("chapters_de/chapter_{num}.txt");
    let status = Command::new("sh")
        .arg("-c")
        .arg(format!("book_parser -l German -f '{}' > '{}'", ch.display(), de))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await?;
    if !status.success() {
        fs::write(format!("failed_book_parser/chapter_{num}.fail"), format!("{num}\n")).unwrap();
        return Err(eyre!("book_parser failed for chapter {num}"));
    }
    Ok(())
}

async fn run_translate(num: u32, wlimit: &str) -> Result<()> {
    let de = format!("chapters_de/chapter_{num}.txt");
    let ti = format!("chapters_ti/chapter_{num}.txt");
    let cmd = format!("translate_infrequent -l de -w {} < '{}' > '{}'", shell_escape(wlimit), de, ti);
    let status = Command::new("sh")
        .arg("-c")
        .arg(cmd)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await?;
    if !status.success() {
        fs::write(format!("failed_translate/chapter_{num}.fail"), format!("{num}\n")).unwrap();
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
