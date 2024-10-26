use clap::{Args, Parser, Subcommand};
use v_utils::io::ExpandedPath;
pub mod config;
use config::AppConfig;

#[derive(Parser, Default)]
#[command(author, version, about, long_about = None)]
struct Cli {
	#[command(subcommand)]
	command: Commands,
	#[arg(long, default_value = "~/.config/PROJECT_NAME_PLACEHOLDER.toml")]
	config: ExpandedPath,
}
#[derive(Subcommand)]
enum Commands {
	Start(StartArgs),
}
impl Default for Commands {
	fn default() -> Self {
		Commands::Start(StartArgs::default())
	}
}

#[derive(Args, Default)]
struct StartArgs {
	arg: String,
}

fn main() {
	let cli = Cli::parse();
	let config = match AppConfig::read(&cli.config.0) {
		Ok(config) => config,
		Err(e) => {
			eprintln!("Error reading config: {e}");
			return;
		}
	};
	match cli.command {
		Commands::Start(args) => start(config, args),
	}
}

fn start(config: AppConfig, args: StartArgs) {
	let message = format!("Hello, {}", args.arg);
	println!("{message}");
}
