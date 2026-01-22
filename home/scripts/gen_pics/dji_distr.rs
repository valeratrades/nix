#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
reqwest = { version = "0.12", features = ["blocking", "rustls-tls"] }
scraper = "0.20"
regex = "1.10"
anyhow = "1.0"
plotters = "0.3"
---

use anyhow::{Context, Result, anyhow, bail};
use clap::Parser;
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
    weight: f64, // percent value, e.g. 6.12
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

    // Locate the main table. Slickcharts uses Bootstrap-ish classes; this is intentionally loose.
    let table_sel = Selector::parse("table").unwrap();
    let thead_sel = Selector::parse("thead th").unwrap();
    let row_sel = Selector::parse("tbody tr").unwrap();
    let cell_sel = Selector::parse("td").unwrap();

    let table = doc
        .select(&table_sel)
        .next()
        .ok_or_else(|| anyhow!("could not find a <table> on the page (format changed?)"))?;

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
        .ok_or_else(|| anyhow!("no 'Company' header found; headers={headers:?}"))?;
    let symbol_i = headers
        .iter()
        .position(|h| h == "Symbol")
        .ok_or_else(|| anyhow!("no 'Symbol' header found; headers={headers:?}"))?;
    let weight_i = headers
        .iter()
        .position(|h| h == "Weight")
        .ok_or_else(|| anyhow!("no 'Weight' header found; headers={headers:?}"))?;

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

fn pie_png(items: &[Item], out: &PathBuf, title: &str) -> Result<()> {
    let root = BitMapBackend::new(out, (1400, 1000)).into_drawing_area();
    root.fill(&WHITE)?;

    let (upper, lower) = root.split_vertically(80);
    upper.draw(&Text::new(title, (20, 35), ("sans-serif", 36).into_font()))?;

    let center = (700, 520);
    let radius = 380;

    let total: f64 = items.iter().map(|x| x.weight).sum();
    if total <= 0.0 {
        bail!("total weight <= 0");
    }

    // Slice angles
    let mut a0 = 0.0f64; // radians
    for (i, it) in items.iter().enumerate() {
        let frac = it.weight / total;
        let a1 = a0 + frac * std::f64::consts::TAU;

        // Plotters colors are limited; cycle through Palette99.
        let col = Palette99::pick(i).mix(0.85).filled();

        lower.draw(&Sector::new(center, radius, a0, a1).style(col))?;

        // Label (symbol/company) and percent
        let mid = (a0 + a1) / 2.0;
        let lx = center.0 as f64 + (radius as f64 + 18.0) * mid.cos();
        let ly = center.1 as f64 - (radius as f64 + 18.0) * mid.sin();

        let pct = 100.0 * frac;
        let label = format!("{:.1}% {}", pct, it.label);

        lower.draw(&Text::new(
            label,
            (lx as i32, ly as i32),
            ("sans-serif", 18).into_font(),
        ))?;

        a0 = a1;
    }

    root.present().context("write png")?;
    Ok(())
}

fn main() -> Result<()> {
    let args = Args::parse();

    let Some(out) = args.out else {
        return Ok(());
    };

    let items = fetch_items(&args.url)?;
    let items = aggregate_top(items, args.top);

    pie_png(
        &items,
        &out,
        "Dow Jones (DJI) composition by weight — slickcharts.com",
    )?;

    Ok(())
}
