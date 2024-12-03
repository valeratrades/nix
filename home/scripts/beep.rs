#!/usr/bin/env cargo
#![allow(clippy::len_zero)]

//! ```cargo
//! [dependencies]
//! clap = { version = "4.2", features = ["derive"] }
//! ```

//HACK: should be implemented with clap, but deps import doesn't yet work in cargo-script (2024/12/03)
use std::process::Command;
//use std::path::PathBuf;
//use clap::Parser;


//#[derive(Parser, Debug)]
//#[command(author, version, about, long_about = None)]
//struct Cli {
//    sound_file: PathBuf,
//	#[arg(long, short)]
//	loud: bool,
//}


//BUG: the loudness arg can **only** be the second arg, because I can't use clap and neither can be bothered
fn beep(mut args: Vec<String>) -> Result<(), String> {
    if args.is_empty() {
        return Err("No file path provided".to_string());
    }
    //let cli = Cli::parse();

    let mut loud = false;
    // fucking hate not having `clap`
    for (i, a) in args.clone().iter().enumerate() {
        if a == "-l" || a == "--loud" {
            loud = true;
            args.remove(i);
        }
    }

    let message: String = if args.len() > 1 {
        args[1..].join(" ").to_owned()
    } else {
        "beep".to_owned()
    };


    let file_path = &args[0];
    match loud {
        //match cli.loud {
        true => {
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
                .args(["-t", "600000" /*10 min*/, &message])
                .status()
                .map_err(|e| e.to_string())?;

            //HACK: should be at 100% volume, this is temporary
            Command::new("ffplay")
                .args(["-nodisp", "-autoexit", "-loglevel", "quiet", file_path])
                .output()
                .map_err(|e| e.to_string())?;

            Ok(())
        }
        false => {
            Command::new("notify-send")
                .arg(message)
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
    if let Err(e) = beep(args) {
        eprintln!("{}", e);
        std::process::exit(1);
    }
}
