#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
reqwest = { version = "0.12", features = ["blocking", "rustls-tls"] }
scraper = "0.20"
regex = "1.10"
color-eyre = "0.6"
plotly = "0.13"
---

use clap::Parser;
use color_eyre::eyre::{bail, Context, Result, eyre};
use std::ffi::OsStr;
use plotly::{
    Pie, Plot,
    common::{Title, Font, Position},
    layout::Layout,
};
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

    /// Output HTML file path (if not specified, does nothing)
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

        let label = format!("{symbol} ({company})");
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

fn create_pie_chart(items: &[Item], title: &str) -> Plot {
    let labels: Vec<String> = items.iter().map(|x| x.label.clone()).collect();
    let values: Vec<f64> = items.iter().map(|x| x.weight).collect();

    let pie = Pie::new(values)
        .labels(labels)
        .text_info("percent+label")
        .text_position(Position::Outside)
        .hole(0.3)
        .sort(false);

    let layout = Layout::new()
        .title(Title::with_text(title).font(Font::new().size(20)))
        .height(900)
        .width(1400)
        .show_legend(true);

    let mut plot = Plot::new();
    plot.add_trace(pie);
    plot.set_layout(layout);
    plot
}

fn main() -> Result<()> {
    color_eyre::install()?;

    let args = Args::parse();

    let Some(out) = args.out else {
        return Ok(());
    };

    if out.extension().and_then(OsStr::to_str) != Some("html") {
        bail!("output file must have .html extension, got: {}", out.display());
    }

    let items = fetch_items(&args.url)?;
    let items = aggregate_top(items, args.top);

    let plot = create_pie_chart(
        &items,
        "Dow Jones Industrial Average (DJI) — Component Weights",
    );

    plot.write_html(&out);

    Ok(())
}
