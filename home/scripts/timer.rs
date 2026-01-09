#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::Parser;
use std::{fs, io::ErrorKind, path::PathBuf, process::Command, thread::sleep, time::Duration};

fn control_file() -> PathBuf {
    PathBuf::from("/tmp/timer_control")
}

// Stolen from ~/s/v_utils/v_utils/src/trades/timeframe.rs
// mod timeframe {{{1
mod timeframe {
    use std::str::FromStr;

    #[derive(Clone, Copy, Debug, Default, PartialEq)]
    pub enum TimeframeDesignator {
        Milliseconds,
        Seconds,
        #[default]
        Minutes,
        Hours,
        Days,
        Weeks,
        Months,
        Quarters,
        Years,
    }
    impl TimeframeDesignator {
        pub const fn as_millis(&self) -> u64 {
            match self {
                TimeframeDesignator::Milliseconds => 1,
                TimeframeDesignator::Seconds => 1_000,
                TimeframeDesignator::Minutes => 60_000,
                TimeframeDesignator::Hours => 3_600_000,
                TimeframeDesignator::Days => 86_400_000,
                TimeframeDesignator::Weeks => 604_800_000,
                TimeframeDesignator::Months => 2_592_000_000,
                TimeframeDesignator::Quarters => 7_776_000_000,
                TimeframeDesignator::Years => 31_536_000_000,
            }
        }
    }

    impl FromStr for TimeframeDesignator {
        type Err = String;

        fn from_str(s: &str) -> Result<Self, Self::Err> {
            match s {
                "ms" => Ok(TimeframeDesignator::Milliseconds),
                "s" => Ok(TimeframeDesignator::Seconds),
                "m" => Ok(TimeframeDesignator::Minutes),
                "min" => Ok(TimeframeDesignator::Minutes),
                "h" | "H" => Ok(TimeframeDesignator::Hours),
                "d" | "D" => Ok(TimeframeDesignator::Days),
                "w" | "W" | "wk" => Ok(TimeframeDesignator::Weeks),
                "M" | "mo" => Ok(TimeframeDesignator::Months),
                "q" | "Q" => Ok(TimeframeDesignator::Quarters),
                "y" | "Y" => Ok(TimeframeDesignator::Years),
                _ => Err(format!("Invalid timeframe designator: {}", s)),
            }
        }
    }

    #[derive(Clone, Copy, Debug, Default, PartialEq)]
    pub struct Timeframe(pub u64);

    impl FromStr for Timeframe {
        type Err = String;

        fn from_str(s: &str) -> Result<Self, Self::Err> {
            if s.is_empty() {
                return Err("Timeframe string is empty".to_string());
            }

            let split_point = s.chars().position(|c| c.is_ascii_alphabetic());

            let (n_str, designator_str) = match split_point {
                Some(pos) => s.split_at(pos),
                None => (s, "m"),
            };

            let designator = TimeframeDesignator::from_str(designator_str)?;

            let n = if n_str.is_empty() {
                1
            } else {
                n_str
                    .parse::<u64>()
                    .map_err(|_| format!("Invalid number in timeframe: '{n_str}'"))?
            };

            Ok(Timeframe(n * designator.as_millis()))
        }
    }

    impl Timeframe {
        pub fn as_secs(&self) -> u64 {
            self.0 / 1_000
        }
    }
}
//,}}}1

/// Countdown timer with visual feedback and notifications
#[derive(Parser, Debug)]
#[command(name = "timer")]
#[command(about = "Countdown timer with visual feedback and notifications")]
struct Args {
    /// Time: seconds (90), mm:ss (1:30), hh:mm:ss (1:30:00), or timeframe (5m, 1h, 30s)
    time: Option<String>,

    /// Halt (pause) the running timer
    #[arg(long, short = 'H')]
    halt: bool,

    /// Resume the paused timer
    #[arg(short, long)]
    resume: bool,

    /// Quiet mode (shows persistent notification instead of beeping)
    #[arg(short, long)]
    quiet: bool,
}

fn parse_time(input: &str) -> Result<i32, String> {
    use std::str::FromStr;

    if input.contains(':') {
        // mm:ss or hh:mm:ss format
        let parts: Vec<&str> = input.split(':').collect();
        match parts.len() {
            2 => {
                let mins: i32 = parts[0].parse::<i32>().map_err(|e| e.to_string())?;
                let secs: i32 = parts[1].parse::<i32>().map_err(|e| e.to_string())?;
                Ok(mins * 60 + secs)
            }
            3 => {
                let hours: i32 = parts[0].parse::<i32>().map_err(|e| e.to_string())?;
                let mins: i32 = parts[1].parse::<i32>().map_err(|e| e.to_string())?;
                let secs: i32 = parts[2].parse::<i32>().map_err(|e| e.to_string())?;
                Ok(hours * 3600 + mins * 60 + secs)
            }
            _ => Err("Time format must be mm:ss or hh:mm:ss".to_string()),
        }
    } else if input.chars().any(|c| c.is_ascii_alphabetic()) {
        // Timeframe format (e.g., 5m, 1h, 30s)
        let tf = timeframe::Timeframe::from_str(input)?;
        Ok(tf.as_secs() as i32)
    } else {
        // Plain seconds
        input.parse::<i32>().map_err(|e| e.to_string())
    }
}

fn read_control() -> Option<String> {
    match fs::read_to_string(control_file()) {
        Ok(s) => Some(s.trim().to_string()),
        Err(e) if e.kind() == ErrorKind::NotFound => None,
        Err(_) => None,
    }
}

fn write_control(state: &str) -> Result<(), String> {
    fs::write(control_file(), state).map_err(|e| e.to_string())
}

fn clear_control() {
    let _ = fs::remove_file(control_file());
}

fn timer(time: &str, quiet: bool) -> Result<(), String> {
    let mut left = parse_time(time)?;

    // Mark as running
    write_control("running")?;

    while left > 0 {
        // Check control file for pause state
        while read_control().as_deref() == Some("paused") {
            sleep(Duration::from_millis(100));
        }

        let hours = left / 3600;
        let mins = (left % 3600) / 60;
        let secs = left % 60;
        let display = if hours > 0 {
            format!("{hours}:{mins:02}:{secs:02}")
        } else {
            format!("{mins}:{secs:02}")
        };
        Command::new("eww")
            .args(["update", &format!("timer={display}")])
            .status()
            .map_err(|e| e.to_string())?;
        sleep(Duration::from_secs(1));
        left -= 1;
    }

    clear_control();

    Command::new("eww")
        .args(["update", "timer="]) // eww things, doing `timer=\"\"` literally sets it to "\"\""
        .status()
        .map_err(|e| e.to_string())?;

    if quiet {
        Command::new("notify-send")
            .args(["timer finished", "-t", "2147483647"])
            .status()
            .map_err(|e| e.to_string())?;
    } else {
        Command::new("fish")
            .args(["-c", "beep --long 600 time"])
            .status()
            .map_err(|e| e.to_string())?;
    }

    Ok(())
}

fn main() {
    let args = Args::parse();

    if args.halt {
        match read_control().as_deref() {
            Some("running") => {
                if let Err(e) = write_control("paused") {
                    eprintln!("{e}");
                    std::process::exit(1);
                }
            }
            Some("paused") => eprintln!("Timer already paused"),
            _ => eprintln!("No timer running"),
        }
        return;
    }

    if args.resume {
        match read_control().as_deref() {
            Some("paused") => {
                if let Err(e) = write_control("running") {
                    eprintln!("{e}");
                    std::process::exit(1);
                }
            }
            Some("running") => eprintln!("Timer already running"),
            _ => eprintln!("No timer to resume"),
        }
        return;
    }

    let Some(time) = args.time else {
        eprintln!("No time specified. Use --help for usage.");
        std::process::exit(1);
    };

    if let Err(e) = timer(&time, args.quiet) {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
