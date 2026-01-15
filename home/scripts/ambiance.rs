#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---
// a thing to procedurally set up environment for performing distinctly different and cognitively demanding tasks

use clap::{Parser, Subcommand};
use std::process::Command;

#[derive(Parser, Debug)]
#[command(name = "ambiance")]
#[command(about = "Set up work ambiance")]
struct Args {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Set up ambiance for learning math
    Math,
}

fn main() {
    let args = Args::parse();

    match args.command {
        Commands::Math => {
            // Set wallpaper
            let _ = Command::new("chromium")
                .args(["https://www.youtube.com/watch?v=gnahH-iQLjQ"])
                .status();

            //DO: move to workspace 8; put it in focus
        }
    }
}
