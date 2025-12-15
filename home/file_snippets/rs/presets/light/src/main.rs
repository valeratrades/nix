use clap::Parser;

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
	value: i64,
}

fn main() {
	color_eyre::install().unwrap();
	let cli = Cli::parse();
	println!("{}", cli.value);
}
