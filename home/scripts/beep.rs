#!/usr/bin/env cargo
#![allow(clippy::len_zero)]

use std::process::Command;

fn beep(args: &[String]) -> Result<(), String> {
    if args.is_empty() {
        return Err("No file path provided".to_string());
    }

    let file_path = &args[0];
    assert!(args.len() == 1);

    match args[0].as_str() {
        "-l" | "--loud" => {
            // TODO: add sound when I figure out how to control volume of other audio sources + have an absolute sound volume filter

            //let mute_status = Command::new("pamixer")
            //    .arg("--get-mute")
            //    .output()
            //    .map_err(|e| e.to_string())?
            //    .stdout;
            //let mute = String::from_utf8_lossy(&mute_status).trim() == "true";
            //
            //if mute {
            //    Command::new("pamixer")
            //        .arg("--unmute")
            //        .status()
            //        .map_err(|e| e.to_string())?;
            //}

            //if mute {
            //    Command::new("pamixer")
            //        .arg("--mute")
            //        .status()
            //        .map_err(|e| e.to_string())?;
            //}

            Command::new("notify-send")
                .arg("beep")
                .arg("-t")
                .arg("600000")
                .status()
                .map_err(|e| e.to_string())?;

            //HACK: should be at 100% volume, this is temporary
            Command::new("ffplay")
                .args(["-nodisp", "-autoexit", "-loglevel", "quiet", file_path])
                .output()
                .map_err(|e| e.to_string())?;

            Ok(())
        }
        _ => {
            Command::new("notify-send")
                .arg("beep")
                .status()
                .map_err(|e| e.to_string())?;
            Command::new("ffplay")
                .args(["-nodisp", "-autoexit", "-loglevel", "quiet", file_path])
                .output()
                .map_err(|e| e.to_string())?;
            Ok(())
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let Err(e) = beep(&args) {
        eprintln!("{}", e);
        std::process::exit(1);
    }
}
