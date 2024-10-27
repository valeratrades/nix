#!/usr/bin/env cargo

use std::env;
use std::process::Command;
use std::thread::sleep;
use std::time::Duration;

fn timer(args: &[String]) -> Result<(), String> {
    if args.contains(&"-h".to_string())
        || args.contains(&"--help".to_string())
        || args.contains(&"help".to_string())
    {
        println!("Usage: timer [time] [-q]\n\nArguments:\n\ttime: time in seconds or in format \"mm:ss\".\n\t-q: quiet mode, shows forever notif instead of beeping.");
        return Ok(());
    }

    let mut beep = true;
    let mut input = "";

    for arg in args {
        if arg == "-q" {
            beep = false;
        } else {
            input = arg;
        }
    }

    let mut left = if input.contains(':') {
        let parts: Vec<&str> = input.split(':').collect();
        let mins: i32 = parts[0].parse::<i32>().map_err(|e| e.to_string())?;
        let secs: i32 = parts[1].parse::<i32>().map_err(|e| e.to_string())?;
        mins * 60 + secs
    } else {
        input.parse::<i32>().map_err(|e| e.to_string())?
    };

    while left > 0 {
        let mins = left / 60;
        let secs = left % 60;
        let formatted_secs = format!("{:02}", secs);
        Command::new("eww")
            .args(["update", &format!("timer={}:{}", mins, formatted_secs)])
            .status()
            .map_err(|e| e.to_string())?;
        sleep(Duration::from_secs(1));
        left -= 1;
    }

    Command::new("eww")
        .args(["update", "timer="]) // eww things, doing `timer=\"\"` literally sets it to "\"\""
        .status()
        .map_err(|e| e.to_string())?;

    if beep {
        Command::new("beep")
            .arg("--loud")
            .status()
            .map_err(|e| e.to_string())?;
    } else {
        Command::new("notify-send")
            .args(["timer finished", "-t", "2147483647"])
            .status()
            .map_err(|e| e.to_string())?;
    }

    Ok(())
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if let Err(e) = timer(&args) {
        eprintln!("{}", e);
        std::process::exit(1);
    }
}
