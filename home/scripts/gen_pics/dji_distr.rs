#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
reqwest = { version = "0.12", features = ["blocking", "rustls-tls"] }
scraper = "0.20"
regex = "1.10"
color-eyre = "0.6"
plotters = { version = "0.3", default-features = false, features = ["svg_backend", "all_elements"] }
resvg = "0.45"
---

use clap::Parser;
use color_eyre::eyre::{bail, Context, Result, eyre};
use plotters::prelude::*;
use regex::Regex;
use reqwest::blocking::Client;
use scraper::{Html, Selector};
use std::cmp::Ordering;
use std::path::PathBuf;

const DEFAULT_URL: &str = "https://www.slickcharts.com/dowjones";

/// Pie chart of Dow Jones component weights from slickcharts.com
#[derive(Parser, Debug)]
#[command(name = "dji_distr")]
#[command(about = "Generate a pie chart of Dow Jones component weights")]
struct Args {
    /// URL to fetch Dow Jones data from
    #[arg(long, default_value = DEFAULT_URL)]
    url: String,

    /// Number of top components to show (0 = no aggregation, rest goes into "OTHER")
    #[arg(long, default_value_t = 12)]
    top: usize,

    /// Output PNG file path (if not specified, does nothing)
    #[arg(short, long)]
    out: Option<PathBuf>,
}

#[derive(Clone, Debug)]
struct Item {
    label: String,
    weight: f64,
}

fn parse_percent(s: &str) -> Result<f64> {
    let t = s.trim().trim_end_matches('%').replace(',', "");
    if t.is_empty() {
        bail!("empty percent");
    }
    Ok(t.parse::<f64>().context("parse percent float")?)
}

fn fetch_items(url: &str) -> Result<Vec<Item>> {
    let client = Client::builder()
        .user_agent("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36")
        .build()
        .context("build http client")?;

    let body = client
        .get(url)
        .send()
        .with_context(|| format!("GET {url}"))?
        .error_for_status()
        .with_context(|| format!("HTTP status for {url}"))?
        .text()
        .context("read response body")?;

    let doc = Html::parse_document(&body);

    let table_sel = Selector::parse("table").unwrap();
    let thead_sel = Selector::parse("thead th").unwrap();
    let row_sel = Selector::parse("tbody tr").unwrap();
    let cell_sel = Selector::parse("td").unwrap();

    let table = doc
        .select(&table_sel)
        .next()
        .ok_or_else(|| eyre!("could not find a <table> on the page (format changed?)"))?;

    let headers: Vec<String> = table
        .select(&thead_sel)
        .map(|th| th.text().collect::<String>().trim().to_string())
        .collect();

    if headers.is_empty() {
        bail!("could not read table headers (missing thead?)");
    }

    let company_i = headers
        .iter()
        .position(|h| h == "Company")
        .ok_or_else(|| eyre!("no 'Company' header found; headers={headers:?}"))?;
    let symbol_i = headers
        .iter()
        .position(|h| h == "Symbol")
        .ok_or_else(|| eyre!("no 'Symbol' header found; headers={headers:?}"))?;
    let weight_i = headers
        .iter()
        .position(|h| h == "Weight")
        .ok_or_else(|| eyre!("no 'Weight' header found; headers={headers:?}"))?;

    let ws_re = Regex::new(r"\s+").unwrap();

    let mut out = Vec::new();
    for tr in table.select(&row_sel) {
        let tds: Vec<_> = tr.select(&cell_sel).collect();
        let need = company_i.max(symbol_i).max(weight_i) + 1;
        if tds.len() < need {
            continue;
        }

        let company_raw = tds[company_i].text().collect::<Vec<_>>().join(" ");
        let symbol_raw = tds[symbol_i].text().collect::<Vec<_>>().join(" ");
        let weight_raw = tds[weight_i].text().collect::<Vec<_>>().join(" ");

        let company = ws_re.replace_all(company_raw.trim(), " ").to_string();
        let symbol = ws_re.replace_all(symbol_raw.trim(), " ").to_string();
        let weight = parse_percent(&weight_raw)?;

        let label = format!("{symbol} — {company}");
        out.push(Item { label, weight });
    }

    if out.is_empty() {
        bail!("parsed 0 components; page layout likely changed");
    }

    Ok(out)
}

fn aggregate_top(mut items: Vec<Item>, top: usize) -> Vec<Item> {
    items.sort_by(|a, b| b.weight.partial_cmp(&a.weight).unwrap_or(Ordering::Equal));

    if top == 0 || items.len() <= top {
        return items;
    }

    let other_weight: f64 = items.iter().skip(top).map(|x| x.weight).sum();
    let mut kept: Vec<Item> = items.into_iter().take(top).collect();
    kept.push(Item {
        label: "OTHER".to_string(),
        weight: other_weight,
    });
    kept
}

fn render_pie_svg(items: &[Item], title: &str) -> String {
    let mut svg = String::new();
    {
        let root = SVGBackend::with_string(&mut svg, (1400, 1000)).into_drawing_area();
        root.fill(&WHITE).unwrap();

        let (upper, lower) = root.split_vertically(80);
        upper
            .draw(&Text::new(title, (20, 35), ("sans-serif", 36).into_font()))
            .unwrap();

        let center = (700i32, 520i32);
        let radius = 300.0;
        let label_offset = 50.0;

        let sizes: Vec<f64> = items.iter().map(|x| x.weight).collect();
        let labels: Vec<String> = items
            .iter()
            .zip(sizes.iter())
            .map(|(it, &w)| {
                let total: f64 = sizes.iter().sum();
                let pct = 100.0 * w / total;
                format!("{:.1}% {}", pct, it.label)
            })
            .collect();
        let label_refs: Vec<&str> = labels.iter().map(|s| s.as_str()).collect();

        let colors: Vec<RGBColor> = (0..items.len())
            .map(|i| {
                let (r, g, b) = Palette99::pick(i).to_rgba().rgb();
                RGBColor(r, g, b)
            })
            .collect();

        let mut pie = Pie::new(&center, &radius, &sizes, &colors, &label_refs);
        pie.label_offset(label_offset);
        pie.label_style(("sans-serif", 16));

        lower.draw(&pie).unwrap();
        root.present().unwrap();
    }
    svg
}

fn svg_to_png(svg_data: &str, out: &PathBuf) -> Result<()> {
    let tree = resvg::usvg::Tree::from_str(svg_data, &resvg::usvg::Options::default())
        .context("parse SVG")?;

    let size = tree.size();
    let width = size.width() as u32;
    let height = size.height() as u32;

    let mut pixmap = resvg::tiny_skia::Pixmap::new(width, height)
        .ok_or_else(|| eyre!("failed to create pixmap"))?;

    resvg::render(&tree, resvg::tiny_skia::Transform::default(), &mut pixmap.as_mut());

    pixmap.save_png(out).context("save PNG")?;
    Ok(())
}

fn main() -> Result<()> {
    color_eyre::install()?;

    let args = Args::parse();

    let Some(out) = args.out else {
        return Ok(());
    };

    let items = fetch_items(&args.url)?;
    let items = aggregate_top(items, args.top);

    let svg = render_pie_svg(
        &items,
        "Dow Jones (DJI) composition by weight — slickcharts.com",
    );

    svg_to_png(&svg, &out)?;

    Ok(())
}
