#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4", features = ["derive"] }
snapshot_fonts = { path = "/home/v/s/snapshot_fonts" }

[dev-dependencies]
insta = "1"
---

use clap::Parser;
use snapshot_fonts::{encode_bars, LEVELS};

const MAX_LEVEL: u8 = (LEVELS - 1) as u8; // 250

fn parse_dims(s: &str) -> Result<(usize, usize), String> {
	let s = s.trim_start_matches('(').trim_end_matches(')');
	let (w, h) = s.split_once(',').ok_or_else(|| format!("expected W,H but got '{s}'"))?;
	let w: usize = w.trim().parse().map_err(|e| format!("bad width: {e}"))?;
	let h: usize = h.trim().parse().map_err(|e| format!("bad height: {e}"))?;
	Ok((w, h))
}

#[derive(Parser)]
#[command(name = "render_to_font")]
struct Args {
	/// Chart width in columns
	#[arg(short = 'W', long, default_value_t = 80)]
	width: usize,

	/// Chart height in rows
	#[arg(short = 'H', long, default_value_t = 20)]
	height: usize,

	/// Dimensions as W,H or (W,H) — overrides --width and --height
	#[arg(short, long, value_parser = parse_dims)]
	dims: Option<(usize, usize)>,
}

fn render(width: usize, height: usize) -> String {
	let total_samples = width * 2;

	let decay_rate = 5.0_f64;
	let memory: Vec<f64> = (0..total_samples)
		.map(|i| {
			let t = i as f64 / (total_samples - 1) as f64;
			(-decay_rate * t).exp()
		})
		.collect();
	let effect: Vec<f64> = (0..total_samples)
		.map(|i| {
			let t = i as f64 / (total_samples - 1) as f64;
			(-decay_rate * (1.0 - t)).exp()
		})
		.collect();

	let mut rows: Vec<String> = Vec::with_capacity(height);
	for row in (0..height).rev() {
		let mut row_str = String::with_capacity(width * 4);
		for col in 0..width {
			let li = col * 2;
			let ri = col * 2 + 1;

			let left_level = sample_level(memory[li], effect[li], row, height);
			let right_level = sample_level(memory[ri], effect[ri], row, height);

			row_str.push(encode_bars(left_level, right_level));
		}
		rows.push(row_str);
	}

	let mut out = rows.join("\n");

	const LEGEND_FULL: &str = "x: time, y(left): memory, y(right): result";
	const LEGEND_SHORT: &str = "memory x result";
	let legend = if width >= LEGEND_FULL.len() {
		Some(LEGEND_FULL)
	} else if width >= LEGEND_SHORT.len() {
		Some(LEGEND_SHORT)
	} else {
		None
	};
	if let Some(legend) = legend {
		let padding = (width - legend.len()) / 2;
		out.push('\n');
		out.push_str(&" ".repeat(padding));
		out.push_str(legend);
	}

	out
}

fn sample_level(memory_val: f64, effect_val: f64, row: usize, height: usize) -> u8 {
	let mem_level = curve_level(memory_val, row, height);
	let eff_level = curve_level(effect_val, row, height);
	mem_level.max(eff_level)
}

fn curve_level(value: f64, row: usize, height: usize) -> u8 {
	let total_units = value * height as f64 * MAX_LEVEL as f64;
	let row_base = row as f64 * MAX_LEVEL as f64;
	(total_units - row_base).clamp(0.0, MAX_LEVEL as f64) as u8
}

fn main() {
	let args = Args::parse();
	let (width, height) = args.dims.unwrap_or((args.width, args.height));
	println!("{}", render(width, height));
}

#[test]
fn legend_short() {
	let output = render(20, 5);
	insta::assert_snapshot!(output, @r"
	󿽦󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󶯰
	󿿽󽼌󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󶳊󿿽
	󿿽󿿽󿶫󵝣󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󱌇󺗇󿿽󿿽
	󿿽󿿽󿿽󿿽󼲗󶠼󱮋󰧥󰧥󰧥󰧥󰧥󰧥󰧷󴀲󹟛󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿯󽖐󺝒󸏦󷕀󹓄󻴦󿉃󿿽󿿽󿿽󿿽󿿽󿿽
	  memory x result
	");
}

#[test]
fn legend_none() {
	let output = render(10, 5);
	insta::assert_snapshot!(output, @r"
	󿼃󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰫟
	󿿕󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󽣅
	󿿽󿎂󰧥󰧥󰧥󰧥󰧥󰧥󴲄󿿽
	󿿽󿿽󼂘󱃂󰧥󰧥󰧬󵷶󿿽󿿽
	󿿽󿿽󿿽󿿉󹽢󷴴󼴁󿿽󿿽󿿽
	");
}

#[test]
fn snapshot() {
	let output = render(80, 20);
	insta::assert_snapshot!(output, @r"
	󿽢󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󶠄
	󿿽󼥇󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󳪳󿿽
	󿿽󿿽󺗠󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󲀖󿿽󿿽
	󿿽󿿽󿿽󹌵󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󱘵󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󹁉󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󱬙󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󹴜󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󲻂󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󻢳󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󵄯󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󾄕󲁲󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧼󷽭󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿾶󶀭󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰨽󻩠󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󺯿󰳖󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧨󵯫󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿾲󶰌󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󲓂󻙴󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󽕥󵂅󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󱈅󹋽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󼪙󵕹󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󱻉󹀁󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󽹐󷛷󱚤󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧲󴘣󺪎󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿛󻈍󵱬󰳖󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧨󳑢󸜕󽺧󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿙󻜁󷄞󲸱󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰻱󴻰󹏙󽲱󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󾙇󺰴󷔖󴃬󱃂󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧥󰧬󲢂󵪸󸿢󼣻󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿭󽦃󺼰󸛖󶅮󳸀󱲉󰧥󰧥󰧥󰧥󰧥󰧥󰳩󲵦󴻠󷑈󹪮󼐇󿁍󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿌢󽚖󻬇󺵛󼟰󾑼󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽󿿽
	                   x: time, y(left): memory, y(right): result
	");
}
