#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
reqwest = { version = "0.12", features = ["blocking", "rustls-tls", "json"] }
scraper = "0.20"
regex = "1.10"
color-eyre = "0.6"
plotly = "0.13"
serde = { version = "1", features = ["derive"] }
---

use clap::{Parser, ValueEnum};
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

#[derive(Clone, Copy, Debug, ValueEnum)]
enum Index {
    /// SPDR Dow Jones Industrial Average ETF
    Dia,
    /// SPDR S&P 500 ETF
    Spy,
    /// Invesco QQQ (Nasdaq-100)
    Qqq,
    /// Top 100 cryptocurrencies by market cap
    Crypto,
}

impl Index {
    fn title(self) -> &'static str {
        match self {
            Index::Dia => "SPDR Dow Jones Industrial Average ETF (DIA) — Holdings",
            Index::Spy => "S&P 500 ETF (SPY) — Holdings",
            Index::Qqq => "Invesco QQQ (Nasdaq-100) — Holdings",
            Index::Crypto => "Cryptocurrency Market Cap Distribution",
        }
    }
}

/// Pie charts of index component weights from slickcharts.com
#[derive(Parser, Debug)]
#[command(name = "indexes")]
#[command(about = "Generate pie charts of index component weights")]
struct Args {
    /// Index to display
    index: Index,

    /// Output HTML file path (if not specified, does nothing)
    #[arg(short, long)]
    out: Option<PathBuf>,

    /// Number of top components to label on the chart (0 = all)
    #[arg(long, default_value_t = 32)]
    top: usize,
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

fn build_client() -> Result<Client> {
    Client::builder()
        .user_agent("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36")
        .build()
        .context("build http client")
}

#[derive(serde::Deserialize)]
struct CoinData {
    name: String,
    symbol: String,
    market_cap: Option<f64>,
}

fn fetch_crypto_items() -> Result<Vec<Item>> {
    let client = build_client()?;
    let url = "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=100&page=1";

    let coins: Vec<CoinData> = client
        .get(url)
        .send()
        .context("GET coingecko")?
        .error_for_status()
        .context("coingecko status")?
        .json()
        .context("parse coingecko json")?;

    let items: Vec<Item> = coins
        .into_iter()
        .filter_map(|c| {
            c.market_cap.map(|mc| Item {
                label: format!("{} ({})", c.symbol.to_uppercase(), c.name),
                weight: mc,
            })
        })
        .collect();

    if items.is_empty() {
        bail!("no crypto data returned");
    }

    Ok(items)
}

fn fetch_etf_items(url: &str) -> Result<Vec<Item>> {
    let client = build_client()?;

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
        .position(|h| h == "Holding")
        .ok_or_else(|| eyre!("no 'Holding' header found; headers={headers:?}"))?;
    let symbol_i = headers
        .iter()
        .position(|h| h == "Symbol")
        .ok_or_else(|| eyre!("no 'Symbol' header found; headers={headers:?}"))?;
    let weight_i = headers
        .iter()
        .position(|h| h == "Portfolio%")
        .ok_or_else(|| eyre!("no 'Portfolio%' header found; headers={headers:?}"))?;

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

fn create_pie_chart(items: &[Item], title: &str, labeled_count: usize) -> Plot {
    let mut items: Vec<_> = items.to_vec();
    items.sort_by(|a, b| b.weight.partial_cmp(&a.weight).unwrap_or(Ordering::Equal));

    let total: f64 = items.iter().map(|x| x.weight).sum();
    let labels: Vec<String> = items.iter().map(|x| x.label.clone()).collect();
    let values: Vec<f64> = items.iter().map(|x| x.weight).collect();
    let text: Vec<String> = items
        .iter()
        .enumerate()
        .map(|(i, x)| {
            if labeled_count == 0 || i < labeled_count {
                let pct = x.weight / total * 100.0;
                format!("{}<br>{:.2}%", x.label, pct)
            } else {
                String::new()
            }
        })
        .collect();

    let pie = Pie::new(values)
        .labels(labels)
        .text_array(text)
        .text_info("text")
        .text_position(Position::Outside)
        .hole(0.3)
        .sort(false)
        .domain(plotly::common::Domain::new().x(&[0.1, 0.6]).y(&[0.1, 0.9]));

    let layout = Layout::new()
        .title(Title::with_text(title).font(Font::new().size(20)))
        .show_legend(false);

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
        html, body {{ margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; display: flex; }}
        #chart {{ flex: 1; height: 100%; }}
        #legend {{
            width: 280px;
            height: 100%;
            overflow-y: auto;
            padding: 10px;
            box-sizing: border-box;
            font-family: sans-serif;
            font-size: 12px;
        }}
        .legend-item {{
            display: flex;
            align-items: center;
            padding: 2px 0;
        }}
        .legend-color {{
            width: 12px;
            height: 12px;
            margin-right: 6px;
            flex-shrink: 0;
        }}
        .legend-label {{
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }}
        .legend-pct {{
            margin-left: 6px;
            color: #666;
        }}
    </style>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
</head>
<body>
    <div id="chart"></div>
    <div id="legend"></div>
    <script>
        var spec = {plot_json};
        var data = spec.data;
        var layout = spec.layout || {{}};
        layout.autosize = true;
        Plotly.newPlot('chart', data, layout, {{responsive: true}});

        var trace = data[0];
        var labels = trace.labels;
        var values = trace.values;
        var total = values.reduce((a, b) => a + b, 0);
        var colors = Plotly.d3.scale.category20().range();

        var legendDiv = document.getElementById('legend');
        for (var i = 0; i < labels.length; i++) {{
            var pct = (values[i] / total * 100).toFixed(2);
            var color = colors[i % colors.length];
            var item = document.createElement('div');
            item.className = 'legend-item';
            item.innerHTML = '<div class="legend-color" style="background:' + color + '"></div>' +
                '<span class="legend-label">' + labels[i] + '</span>' +
                '<span class="legend-pct">' + pct + '%</span>';
            legendDiv.appendChild(item);
        }}
    </script>
</body>
</html>"##
    );
    std::fs::write(path, html).context("write html")?;
    Ok(())
}

fn main() -> Result<()> {
    color_eyre::install()?;

    let args = Args::parse();

    let Some(out) = args.out else {
        return Ok(());
    };

    if out.extension().and_then(OsStr::to_str) != Some("html") {
        bail!(
            "output file must have .html extension, got: {}",
            out.display()
        );
    }

    let index = args.index;
    let items = match index {
        Index::Crypto => {
            eprintln!("HINT: https://coin360.com/ — superior version of what we're pitifully trying to do");
            fetch_crypto_items()?
        }
        Index::Dia => fetch_etf_items("https://www.slickcharts.com/symbol/DIA/holdings")?,
        Index::Spy => fetch_etf_items("https://www.slickcharts.com/symbol/SPY/holdings")?,
        Index::Qqq => fetch_etf_items("https://www.slickcharts.com/symbol/QQQ/holdings")?,
    };
    let plot = create_pie_chart(&items, index.title(), args.top);
    write_responsive_html(&plot, &out)?;

    Ok(())
}
