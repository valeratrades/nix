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

use clap::{Parser, Subcommand};
use color_eyre::eyre::{Context, Result, bail, eyre};
use plotly::{
    Pie, Plot,
    common::{Font, Position, Title},
    layout::Layout,
};
use regex::Regex;
use reqwest::blocking::Client;
use scraper::{Html, Selector};
use std::cmp::Ordering;
use std::ffi::OsStr;
use std::path::PathBuf;

const DJI_URL: &str = "https://www.slickcharts.com/dowjones";
const SPY_URL: &str = "https://www.slickcharts.com/symbol/SPY/holdings";

/// Pie charts of index component weights from slickcharts.com
#[derive(Parser, Debug)]
#[command(name = "indexes")]
#[command(about = "Generate pie charts of index component weights")]
struct Args {
    /// Output HTML file path (if not specified, does nothing)
    #[arg(short, long)]
    out: Option<PathBuf>,

    /// Number of top components to show (0 = no aggregation, rest goes into "OTHER")
    #[arg(long, default_value_t = 32)]
    top: usize,

    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Dow Jones Industrial Average components
    Dji,
    /// S&P 500 ETF (SPY) holdings
    Spy,
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

fn fetch_items(url: &str, company_header: &str, weight_header: &str) -> Result<Vec<Item>> {
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
        .position(|h| h == company_header)
        .ok_or_else(|| eyre!("no '{company_header}' header found; headers={headers:?}"))?;
    let symbol_i = headers
        .iter()
        .position(|h| h == "Symbol")
        .ok_or_else(|| eyre!("no 'Symbol' header found; headers={headers:?}"))?;
    let weight_i = headers
        .iter()
        .position(|h| h == weight_header)
        .ok_or_else(|| eyre!("no '{weight_header}' header found; headers={headers:?}"))?;

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
        .sort(false)
        .domain(plotly::common::Domain::new().x(&[0.25, 0.75]).y(&[0.15, 0.85]));

    let layout = Layout::new()
        .title(Title::with_text(title).font(Font::new().size(20)))
        .show_legend(true);

    let mut plot = Plot::new();
    plot.add_trace(pie);
    plot.set_layout(layout);
    plot
}

fn write_responsive_html(plot: &Plot, path: &std::path::Path) -> Result<()> {
    let plot_json = plot.to_json();
    let html = format!(
        r##"<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        html, body {{ margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; }}
        #chart {{ width: 100%; height: 100%; }}
    </style>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
</head>
<body>
    <div id="chart"></div>
    <script>
        var spec = {plot_json};
        var data = spec.data;
        var layout = spec.layout || {{}};
        layout.autosize = true;
        Plotly.newPlot('chart', data, layout, {{responsive: true}});
    </script>
</body>
</html>"##
    );
    std::fs::write(path, html).context("write html")?;
    Ok(())
}

fn run(
    out: Option<PathBuf>,
    url: &str,
    company_header: &str,
    weight_header: &str,
    title: &str,
    top: usize,
) -> Result<()> {
    let Some(out) = out else {
        return Ok(());
    };

    if out.extension().and_then(OsStr::to_str) != Some("html") {
        bail!(
            "output file must have .html extension, got: {}",
            out.display()
        );
    }

    let items = fetch_items(url, company_header, weight_header)?;
    let items = aggregate_top(items, top);

    let plot = create_pie_chart(&items, title);
    write_responsive_html(&plot, &out)?;

    Ok(())
}

fn main() -> Result<()> {
    color_eyre::install()?;

    let args = Args::parse();

    match args.cmd {
        Cmd::Dji => run(
            args.out,
            DJI_URL,
            "Company",
            "Weight",
            "Dow Jones Industrial Average (DJI) — Component Weights",
            args.top,
        ),
        Cmd::Spy => run(
            args.out,
            SPY_URL,
            "Holding",
            "Portfolio%",
            "S&P 500 ETF (SPY) — Top Holdings",
            args.top,
        ),
    }
}
