#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
rand = "0.8"
---

use clap::Parser;
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};

/// k-armed bandit — start a game server or pull a lever
#[derive(Parser, Debug)]
struct Cli {
	#[command(subcommand)]
	command: Command,
}

#[derive(clap::Subcommand, Debug, Clone)]
enum Command {
	Start(StartArgs),
	Pull(PullArgs),
	Info,
}

#[derive(clap::Args, Debug, Clone)]
struct StartArgs {
	#[arg(default_value_t = 100)]
	tries: usize,
	#[arg(long, short, default_value_t = 10)]
	n_levers: usize,
}

#[derive(clap::Args, Debug, Clone)]
struct PullArgs {
	#[arg(short, long)]
	lever: usize,
}

struct GameState {
	lever_values: Vec<f64>,
	lever_pulls: Vec<usize>,
	lever_wins: Vec<usize>,
	tries_left: usize,
	wins: usize,
}

impl GameState {
	fn build(n_levers: usize, tries: usize) -> Self {
		//DO: init random
		//REVIEW
		let lever_values = (0..n_levers).map(|_| rand::random::<f64>()).collect();
		GameState {
			lever_values,
			lever_pulls: vec![0; n_levers],
			lever_wins: vec![0; n_levers],
			tries_left: tries,
			wins: 0,
		}
	}

	fn pull(&mut self, lever: usize) -> Result<(u8, usize, usize), String> {
		if self.tries_left == 0 {
			return Err("no tries left".to_string());
		}
		if lever >= self.lever_values.len() {
			return Err(format!(
				"lever {} out of range (0..{})",
				lever,
				self.lever_values.len()
			));
		}
		let success = rand::random::<f64>() < self.lever_values[lever];
		self.tries_left -= 1;
		self.lever_pulls[lever] += 1;
		self.lever_wins[lever] += success as usize;
		self.wins += success as usize;
		Ok((success as u8, self.tries_left, self.wins))
	}
}

fn handle_client(stream: TcpStream, state: &mut GameState) {
	let mut buf = String::new();
	BufReader::new(&stream).read_line(&mut buf).expect("read from client");
	let response = match buf.trim() {
		cmd if cmd.starts_with("PULL ") => match cmd["PULL ".len()..].trim().parse::<usize>() {
			Ok(lever) => match state.pull(lever) {
				Ok((payoff, tries_left, wins)) => format!("OK {} {} {}\n", payoff, tries_left, wins),
				Err(e) => format!("ERR {}\n", e),
			},
			Err(_) => "ERR invalid lever index\n".to_string(),
		},
		"INFO" => {
			// "OK <pulls0> <wins0> <pulls1> <wins1> ..."
			let stats: Vec<String> = state
				.lever_pulls
				.iter()
				.zip(state.lever_wins.iter())
				.map(|(p, w)| format!("{} {}", p, w))
				.collect();
			format!("OK {}\n", stats.join(" "))
		}
		_ => "ERR unknown command\n".to_string(),
	};
	(&stream).write_all(response.as_bytes()).expect("write to client");
}

fn connect() -> TcpStream {
	TcpStream::connect("127.0.0.1:65379")
		.expect("connect to game server — is it running? (start with `k_armed_bandit.rs start`)")
}

fn main() {
	let cli = Cli::parse();

	match cli.command {
		Command::Start(args) => {
			//DO: this starts service running over TCP on 65379
			//REVIEW
			let mut state = GameState::build(args.n_levers, args.tries);
			let listener = TcpListener::bind("127.0.0.1:65379").expect("bind :65379");
			println!(
				"started: {} levers, {} tries — listening on 127.0.0.1:65379",
				args.n_levers, args.tries
			);
			for stream in listener.incoming() {
				handle_client(stream.expect("accept connection"), &mut state);
				if state.tries_left == 0 {
					println!("game over: {} wins out of {} tries", state.wins, args.tries);
					break;
				}
			}
		}
		Command::Pull(args) => {
			//DO: assert level within the range
			//DO: allows to pull a chosen level once
			//DO: check payoff, -1 the tries left
			//REVIEW (all handled server-side; ERR is returned for out-of-range)
			let mut stream = connect();
			stream
				.write_all(format!("PULL {}\n", args.lever).as_bytes())
				.expect("send pull");
			let mut response = String::new();
			BufReader::new(&stream).read_line(&mut response).expect("read response");
			match response.trim() {
				r if r.starts_with("OK ") => {
					let mut parts = r["OK ".len()..].split_whitespace();
					let payoff: u8 = parts.next().expect("payoff").parse().expect("payoff u8");
					let tries_left: usize =
						parts.next().expect("tries_left").parse().expect("tries_left usize");
					let wins: usize = parts.next().expect("wins").parse().expect("wins usize");
					let outcome = if payoff == 1 { "win" } else { "loss" };
					println!(
						"lever {}: {}  |  wins: {}  |  tries left: {}",
						args.lever, outcome, wins, tries_left
					);
				}
				r if r.starts_with("ERR ") => {
					eprintln!("error: {}", &r["ERR ".len()..]);
					std::process::exit(1);
				}
				r => {
					eprintln!("unexpected response: {r}");
					std::process::exit(1);
				}
			}
		}
		Command::Info => {
			let mut stream = connect();
			stream.write_all(b"INFO\n").expect("send INFO");
			let mut response = String::new();
			BufReader::new(&stream).read_line(&mut response).expect("read response");
			match response.trim() {
				r if r.starts_with("OK ") => {
					let nums: Vec<usize> = r["OK ".len()..]
						.split_whitespace()
						.map(|s| s.parse().expect("stat integer"))
						.collect();
					// pairs: pulls, wins per lever
					let levers: Vec<(usize, usize)> = nums
						.chunks(2)
						.map(|c| (c[0], c[1]))
						.collect();
					print_info_table(&levers);
				}
				r if r.starts_with("ERR ") => {
					eprintln!("error: {}", &r["ERR ".len()..]);
					std::process::exit(1);
				}
				r => {
					eprintln!("unexpected response: {r}");
					std::process::exit(1);
				}
			}
		}
	}
}

fn print_info_table(levers: &[(usize, usize)]) {
	let col_w = [5usize, 5, 4, 10]; // lever, pulls, wins, avg
	let header = format!(
		" {:>w0$} | {:>w1$} | {:>w2$} | {:<w3$}",
		"lever", "pulls", "wins", "avg payout",
		w0 = col_w[0], w1 = col_w[1], w2 = col_w[2], w3 = col_w[3],
	);
	let sep = format!(
		"-{}-+-{}-+-{}-+-{}-",
		"-".repeat(col_w[0]),
		"-".repeat(col_w[1]),
		"-".repeat(col_w[2]),
		"-".repeat(col_w[3]),
	);
	println!("{}", header);
	println!("{}", sep);
	for (i, (pulls, wins)) in levers.iter().enumerate() {
		let avg = if *pulls == 0 {
			"  n/a".to_string()
		} else {
			format!("{:.3}", *wins as f64 / *pulls as f64)
		};
		println!(
			" {:>w0$} | {:>w1$} | {:>w2$} | {:<w3$}",
			i, pulls, wins, avg,
			w0 = col_w[0], w1 = col_w[1], w2 = col_w[2], w3 = col_w[3],
		);
	}
}
