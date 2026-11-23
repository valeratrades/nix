#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
jiff = "0.2"
miette = { version = "7", features = ["fancy"] }
reqwest = { version = "0.12", default-features = false, features = ["blocking", "json", "rustls-tls"] }
serde_json = "1"
thiserror = "2"
v_utils = { version = "2.26", default-features = false }
---

use std::{
    collections::BTreeMap,
    io::{BufRead, BufReader, Write},
    net::TcpListener,
    process::Command,
    str::FromStr,
    time::Duration,
};

use clap::Parser;
use miette::{Diagnostic, IntoDiagnostic, Result, bail, miette};
use jiff::{
    SignedDuration, Span, Timestamp,
    civil::{Date, DateTime},
    tz::TimeZone,
};
use reqwest::{Method, Url, blocking::Client};
use serde_json::{Value, json};
use v_utils::{SignedTimeframe, Timeframe};

const API: &str = "https://www.googleapis.com/calendar/v3";
const AUTH_URL: &str = "https://accounts.google.com/o/oauth2/v2/auth";
const TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
const SCOPE: &str = "https://www.googleapis.com/auth/calendar";
const DAY_MS: i64 = 86_400_000;
const TOKEN_VAR: &str = "GOOGLE_CALENDAR_REFRESH_TOKEN";

#[derive(Debug, thiserror::Error, Diagnostic)]
enum CalendarLookup {
    #[error("no calendar is named {query:?} on this account")]
    #[diagnostic(help("its calendars:\n{available}"))]
    Missing { query: String, available: String },
    #[error("{n} calendars are named {query:?}")]
    #[diagnostic(help("pass one of their ids instead:\n{ids}"))]
    Ambiguous { query: String, n: usize, ids: String },
}

/// Shift a Google Calendar's own events starting in [today, today + forward) by an offset.
/// A recurring series moves from its first instance in that window on, wherever its later instances land.
#[derive(Parser)]
struct Args {
    /// calendar name, as in the sidebar, or its id
    calendar: String,
    /// e.g. +1h, -30m
    #[arg(allow_hyphen_values = true, value_parser = SignedTimeframe::from_str)]
    offset: SignedTimeframe,
    #[arg(short, long, default_value = "1w", value_parser = Timeframe::from_str)]
    forward: Timeframe,
    /// print the changes, write nothing
    #[arg(short = 'n', long)]
    dry_run: bool,
}

fn main() -> Result<()> {
    let args = Args::parse();
    let http = Client::new();
    let api = Api { token: access_token(&http)?, http, dry_run: args.dry_run };

    let all = api.get_all(&["users", "me", "calendarList"], &[])?;
    let listed = |cals: &[&Value]| cals.iter().map(|c| format!("  {}  ({})", c["summary"].as_str().unwrap_or("?"), c["id"].as_str().unwrap_or("?"))).collect::<Vec<_>>().join("\n"); // display only
    let cals: Vec<&Value> = all.iter().filter(|c| c["summary"] == args.calendar.as_str() || c["id"] == args.calendar.as_str()).collect();
    let cal = match cals.as_slice() {
        [cal] => *cal,
        [] => Err(CalendarLookup::Missing { query: args.calendar.clone(), available: all.iter().map(|c| format!("  {}", c["summary"].as_str().unwrap_or("?"))).collect::<Vec<_>>().join("\n") })?, // display only
        _ => Err(CalendarLookup::Ambiguous { query: args.calendar.clone(), n: cals.len(), ids: listed(&cals) })?,
    };
    let cal_id = str_of(&cal["id"])?;
    let tz = TimeZone::get(str_of(&cal["timeZone"])?).into_diagnostic()?;

    let today = Timestamp::now().to_zoned(tz.clone()).start_of_day().into_diagnostic()?;
    let from = today.timestamp();
    let to = from + SignedDuration::try_from(args.forward.duration()).into_diagnostic()?;
    let off = SignedDuration::from_millis(args.offset.0);
    let window = Window { from, day: today.date() };

    let items = api.get_all(&["calendars", cal_id, "events"], &[
        ("singleEvents", "true"),
        ("orderBy", "startTime"),
        ("timeMin", &from.to_string()),
        ("timeMax", &to.to_string()),
    ])?;
    let mut series: BTreeMap<String, Vec<Value>> = BTreeMap::new();
    for ev in items {
        let name = ev["summary"].as_str().unwrap_or("(no title)"); // the API omits an empty title
        let start = When::of(&ev["start"])?;
        if !window.holds(start) {
            continue; // began before today
        }
        if ev["eventType"] != "default" {
            println!("skip {name}: eventType {}", ev["eventType"]);
            continue;
        }
        if ev["organizer"]["self"] != true {
            println!("skip {name}: organized by {}", ev["organizer"]["email"]);
            continue;
        }
        match ev["recurringEventId"].as_str() {
            Some(master) => series.entry(master.to_owned()).or_default().push(ev),
            None => shift_single(&api, cal_id, &ev, off)?,
        }
    }
    for (master, instances) in series {
        let Some(id) = shift_series(&api, cal_id, &master, &instances[0], off, &window, &tz)? else { continue };
        // the series write re-generates instances at their slots; one moved by hand is moved again
        for ev in instances.iter().filter(|ev| ev["start"] != ev["originalStartTime"]) {
            let slot = When::of(&ev["originalStartTime"])?.shift(off).expect("its series shifted");
            let new = match api.dry_run {
                true => None,
                false => api.call(Method::GET, &["calendars", cal_id, "events", &id, "instances"], &[("originalStart", &slot.json(&json!({}))["dateTime"].as_str().ok_or_else(|| miette!("an all-day exception moved by hand"))?.to_owned())], None)?["items"]
                    .as_array()
                    .and_then(|i| i.first().cloned()),
            };
            match new {
                Some(new) => shift_single(&api, cal_id, &json!({ "id": new["id"], "summary": ev["summary"], "start": ev["start"], "end": ev["end"] }), off)?,
                None if api.dry_run => println!("{}: moved instance @ {} keeps its own time", ev["summary"].as_str().unwrap_or("(no title)"), When::of(&ev["start"])?), // the API omits an empty title
                None => bail!("series {id} has no instance at {slot} after the shift"),
            }
        }
    }
    Ok(())
}

fn shift_single(api: &Api, cal: &str, ev: &Value, off: SignedDuration) -> Result<()> {
    let name = ev["summary"].as_str().unwrap_or("(no title)"); // the API omits an empty title
    let (s, e) = (When::of(&ev["start"])?, When::of(&ev["end"])?);
    let (Some(ns), Some(ne)) = (s.shift(off), e.shift(off)) else {
        println!("skip {name}: all-day, offset is not whole days");
        return Ok(());
    };
    println!("{name}: {s} -> {ns}");
    api.write(Method::PATCH, &["calendars", cal, "events", str_of(&ev["id"])?], &json!({
        "start": ns.json(&ev["start"]),
        "end": ne.json(&ev["end"]),
    }))?;
    Ok(())
}

/// Starts in the window: the whole series moves. Else it is split at `first`: the old one ends before it, a shifted copy carries on.
/// Returns the id of the series that carries on; `None` when skipped, or split in a dry run.
fn shift_series(api: &Api, cal: &str, id: &str, first: &Value, off: SignedDuration, window: &Window, cal_tz: &TimeZone) -> Result<Option<String>> {
    let master = api.call(Method::GET, &["calendars", cal, "events", id], &[], None)?;
    let name = master["summary"].as_str().unwrap_or("(no title)"); // the API omits an empty title
    let (ms, me) = (When::of(&master["start"])?, When::of(&master["end"])?);
    let Some(shifted_start) = ms.shift(off) else {
        println!("skip series {name}: all-day, offset is not whole days");
        return Ok(None);
    };
    let tz = match master["start"]["timeZone"].as_str() {
        Some(t) => TimeZone::get(t).into_diagnostic()?,
        None => cal_tz.clone(),
    };
    let rec: Vec<String> = master["recurrence"]
        .as_array()
        .ok_or_else(|| miette!("series {id} has no recurrence"))?
        .iter()
        .map(|l| str_of(l).map(str::to_owned))
        .collect::<Result<_>>()?;
    let mut shifted_rec = shift_recurrence(&rec, off, &tz)?;

    let len = match (ms, me) {
        (When::At(a), When::At(b)) => b.duration_since(a),
        (When::Day(a), When::Day(b)) => SignedDuration::from_hours(24 * i64::from((b - a).get_days())),
        _ => bail!("series {id}: start and end are of different kinds"),
    };
    let copy_from = |at: When, rec: &[String]| {
        let mut copy = master.clone();
        let obj = copy.as_object_mut().expect("an event is an object");
        for k in ["id", "iCalUID", "etag", "htmlLink", "created", "updated", "sequence", "creator", "organizer", "recurringEventId", "originalStartTime"] {
            obj.remove(k);
        }
        obj.insert("start".into(), at.shift(off).expect("checked on the series start").json(&master["start"]));
        obj.insert("end".into(), at.shift(off + len).expect("checked on the series start").json(&master["end"]));
        obj.insert("recurrence".into(), json!(rec));
        copy
    };
    // insert before cutting the old one short: a failure between the two leaves a duplicate, not a gap
    let insert = |copy: &Value| api.write(Method::POST, &["calendars", cal, "events"], copy).and_then(|new| new.map(|n| str_of(&n["id"]).map(str::to_owned)).transpose());

    if window.holds(ms) {
        println!("series {name}: {ms} -> {shifted_start}");
        // Google answers "Invalid start time" to moving a series it split off itself (`<id>_R<start>`), so it is replaced
        if id.contains("_R") {
            let new = insert(&copy_from(ms, &shifted_rec))?;
            api.write(Method::DELETE, &["calendars", cal, "events", id], &Value::Null)?;
            return Ok(new);
        }
        let shifted_end = me.shift(off).expect("start shifted, so the offset fits its kind");
        api.write(Method::PATCH, &["calendars", cal, "events", id], &json!({
            "start": shifted_start.json(&master["start"]),
            "end": shifted_end.json(&master["end"]),
            "recurrence": shifted_rec,
        }))?;
        return Ok(Some(id.to_owned()));
    }

    let split = When::of(&first["originalStartTime"])?;
    let split_ts = match split {
        When::At(ts) => ts,
        When::Day(d) => d.to_zoned(tz.clone()).into_diagnostic()?.timestamp(),
    };
    if let Some(count) = rrule_param(&rec, "COUNT") {
        let before = api.get_all(&["calendars", cal, "events", id, "instances"], &[("timeMax", &split_ts.to_string()), ("showDeleted", "true")])?.len();
        let left = count.parse::<usize>().into_diagnostic()?.checked_sub(before).ok_or_else(|| miette!("series {id}: {before} instances before the split, COUNT={count}"))?;
        shifted_rec = shifted_rec.into_iter().map(|l| set_rrule_param(&l, "COUNT", Some(&left.to_string()))).collect();
    }
    let until = match split {
        When::At(ts) => (ts - SignedDuration::from_secs(1)).strftime("%Y%m%dT%H%M%SZ").to_string(),
        When::Day(d) => d.yesterday().into_diagnostic()?.strftime("%Y%m%d").to_string(),
    };
    let old_rec: Vec<String> = rec.iter().map(|l| set_rrule_param(&set_rrule_param(l, "COUNT", None), "UNTIL", Some(&until))).collect();

    println!("series {name}: split at {split}, continues from {}", split.shift(off).expect("checked on the series start"));
    let new = insert(&copy_from(split, &shifted_rec))?;
    api.write(Method::PATCH, &["calendars", cal, "events", id], &json!({ "recurrence": old_rec }))?;
    Ok(new)
}

/// Moves the absolute times of RRULE UNTIL, EXDATE and RDATE with the series.
fn shift_recurrence(lines: &[String], off: SignedDuration, tz: &TimeZone) -> Result<Vec<String>> {
    lines
        .iter()
        .map(|line| {
            let (head, value) = line.split_once(':').ok_or_else(|| miette!("recurrence line without ':': {line}"))?;
            let mut params = head.split(';');
            Ok(match params.next() {
                Some("RRULE") => match rrule_param(std::slice::from_ref(line), "UNTIL") {
                    Some(u) => set_rrule_param(line, "UNTIL", Some(&shift_ical(&u, off, &TimeZone::UTC)?)),
                    None => line.clone(),
                },
                Some("EXDATE" | "RDATE") => {
                    let tz = match params.find_map(|p| p.strip_prefix("TZID=")) {
                        Some(t) => TimeZone::get(t).into_diagnostic()?,
                        None => tz.clone(),
                    };
                    let shifted = value.split(',').map(|v| shift_ical(v, off, &tz)).collect::<Result<Vec<_>>>()?;
                    format!("{head}:{}", shifted.join(","))
                }
                _ => line.clone(),
            })
        })
        .collect()
}

/// iCal DATE, UTC DATE-TIME (`Z`) or a DATE-TIME local to `tz`, shifted in the same form.
fn shift_ical(v: &str, off: SignedDuration, tz: &TimeZone) -> Result<String> {
    Ok(if v.len() == 8 {
        match When::Day(Date::strptime("%Y%m%d", v).into_diagnostic()?).shift(off) {
            Some(When::Day(d)) => d.strftime("%Y%m%d").to_string(),
            _ => bail!("date {v} can't move by {off}"),
        }
    } else if let Some(utc) = v.strip_suffix('Z') {
        (DateTime::strptime("%Y%m%dT%H%M%S", utc).into_diagnostic()?.to_zoned(TimeZone::UTC).into_diagnostic()?.timestamp() + off).strftime("%Y%m%dT%H%M%SZ").to_string()
    } else {
        DateTime::strptime("%Y%m%dT%H%M%S", v).into_diagnostic()?.to_zoned(tz.clone()).into_diagnostic()?.checked_add(off).into_diagnostic()?.datetime().strftime("%Y%m%dT%H%M%S").to_string()
    })
}

fn rrule_param(lines: &[String], key: &str) -> Option<String> {
    let rule = lines.iter().find_map(|l| l.strip_prefix("RRULE:"))?;
    rule.split(';').find_map(|kv| kv.strip_prefix(key)?.strip_prefix('=')).map(str::to_owned)
}

/// Sets (or with `None` removes) `key` on an RRULE line; other lines pass through.
fn set_rrule_param(line: &str, key: &str, value: Option<&str>) -> String {
    let Some(rule) = line.strip_prefix("RRULE:") else { return line.to_owned() };
    let mut parts: Vec<String> = rule.split(';').filter(|kv| kv.split_once('=').map(|(k, _)| k) != Some(key)).map(str::to_owned).collect();
    if let Some(v) = value {
        parts.push(format!("{key}={v}"));
    }
    format!("RRULE:{}", parts.join(";"))
}

struct Window {
    from: Timestamp,
    day: Date,
}
impl Window {
    fn holds(&self, w: When) -> bool {
        match w {
            When::At(ts) => ts >= self.from,
            When::Day(d) => d >= self.day,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum When {
    At(Timestamp),
    Day(Date),
}
impl When {
    fn of(v: &Value) -> Result<Self> {
        if let Some(s) = v["dateTime"].as_str() {
            return Ok(Self::At(s.parse().into_diagnostic()?));
        }
        Ok(Self::Day(v["date"].as_str().ok_or_else(|| miette!("neither dateTime nor date: {v}"))?.parse().into_diagnostic()?))
    }

    /// `None`: a whole-day value can't move by a part of a day.
    fn shift(self, off: SignedDuration) -> Option<Self> {
        match self {
            Self::At(ts) => Some(Self::At(ts + off)),
            Self::Day(d) => {
                let ms = off.as_millis() as i64;
                (ms % DAY_MS == 0).then(|| Self::Day(d.checked_add(Span::new().days(ms / DAY_MS)).expect("calendar dates are far from jiff's bounds")))
            }
        }
    }

    /// Keeps the `timeZone` of the value it replaces.
    fn json(self, orig: &Value) -> Value {
        match self {
            Self::At(ts) => match orig.get("timeZone") {
                Some(tz) => json!({ "dateTime": ts.to_string(), "timeZone": tz }),
                None => json!({ "dateTime": ts.to_string() }),
            },
            Self::Day(d) => json!({ "date": d.to_string() }),
        }
    }
}
impl std::fmt::Display for When {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::At(ts) => write!(f, "{}", ts.strftime("%a %F %H:%M UTC")),
            Self::Day(d) => write!(f, "{}", d.strftime("%a %F")),
        }
    }
}

fn str_of(v: &Value) -> Result<&str> {
    v.as_str().ok_or_else(|| miette!("expected a string, got {v}"))
}

struct Api {
    http: Client,
    token: String,
    dry_run: bool,
}
impl Api {
    fn call(&self, method: Method, path: &[&str], query: &[(&str, &str)], body: Option<&Value>) -> Result<Value> {
        let mut url = Url::parse(API).into_diagnostic()?;
        url.path_segments_mut().expect("API is a base url").extend(path);
        let mut req = self.http.request(method.clone(), url).bearer_auth(&self.token).query(query);
        if let Some(b) = body.filter(|b| !b.is_null()) {
            req = req.json(b);
        }
        let resp = req.send().into_diagnostic()?;
        let status = resp.status();
        let text = resp.text().into_diagnostic()?;
        if !status.is_success() {
            bail!("{method} {}: {status}: {text}", path.join("/"));
        }
        match text.is_empty() {
            true => Ok(Value::Null), // DELETE answers 204
            false => serde_json::from_str(&text).into_diagnostic(),
        }
    }

    fn get_all(&self, path: &[&str], query: &[(&str, &str)]) -> Result<Vec<Value>> {
        let mut out = Vec::new();
        let mut page: Option<String> = None;
        loop {
            let mut q = query.to_vec();
            q.push(("maxResults", "250"));
            if let Some(p) = &page {
                q.push(("pageToken", p));
            }
            let mut resp = self.call(Method::GET, path, &q, None)?;
            match resp["items"].take() {
                Value::Array(items) => out.extend(items),
                Value::Null => {}
                v => bail!("items is not a list: {v}"),
            }
            match resp["nextPageToken"].as_str() {
                Some(p) => page = Some(p.to_owned()),
                None => return Ok(out),
            }
        }
    }

    /// `None` in a dry run.
    fn write(&self, method: Method, path: &[&str], body: &Value) -> Result<Option<Value>> {
        match self.dry_run {
            true => Ok(None),
            false => self.call(method, path, &[("eventLabelVersion", "1")], Some(body)).map(Some), // without it `eventLabelId` (the event's color label) is dropped
        }
    }
}

/// Shared with other tools reading the env var; re-consent writes it back where fish sources it from.
fn access_token(http: &Client) -> Result<String> {
    let id = std::env::var("GOOGLE_CLIENT_ID").map_err(|_| miette!("GOOGLE_CLIENT_ID is not set"))?;
    let secret = std::env::var("GOOGLE_CLIENT_SECRET").map_err(|_| miette!("GOOGLE_CLIENT_SECRET is not set"))?;
    let mut refresh = std::env::var(TOKEN_VAR).ok(); // unset: asked for below
    loop {
        let Some(token) = &refresh else {
            let token = consent(http, &id, &secret)?;
            persist_refresh_token(&token)?;
            refresh = Some(token);
            continue;
        };
        let resp: Value = http
            .post(TOKEN_URL)
            .form(&[("client_id", id.as_str()), ("client_secret", &secret), ("refresh_token", token), ("grant_type", "refresh_token")])
            .send()
            .into_diagnostic()?
            .json()
            .into_diagnostic()?;
        if resp["error"] == "invalid_grant" {
            eprintln!("{TOKEN_VAR} was revoked or expired, asking Google again");
            refresh = None;
            continue;
        }
        return Ok(str_of(&resp["access_token"]).map_err(|_| miette!("token refresh: {resp}"))?.to_owned());
    }
}

fn persist_refresh_token(token: &str) -> Result<()> {
    let path = format!("{}/s/g/private/credentials.fish", std::env::var("HOME").into_diagnostic()?);
    let text = std::fs::read_to_string(&path).into_diagnostic()?;
    let prefix = format!("set -x {TOKEN_VAR} ");
    let n = text.lines().filter(|l| l.starts_with(&prefix)).count();
    if n != 1 {
        bail!(help = "the line is rewritten in place", "{path} sets {TOKEN_VAR} {n} times, expected once");
    }
    let new: Vec<String> = text.lines().map(|l| if l.starts_with(&prefix) { format!("{prefix}\"{token}\"") } else { l.to_owned() }).collect();
    std::fs::write(&path, new.join("\n") + "\n").into_diagnostic()?;
    eprintln!("{TOKEN_VAR} renewed in {path}; shells started before this still hold the old one");
    Ok(())
}

/// OAuth loopback flow: the browser comes back to a one-shot listener with the code.
fn consent(http: &Client, id: &str, secret: &str) -> Result<String> {
    let listener = TcpListener::bind("127.0.0.1:0").into_diagnostic()?;
    let redirect = format!("http://127.0.0.1:{}", listener.local_addr().into_diagnostic()?.port());
    let url = Url::parse_with_params(AUTH_URL, &[
        ("client_id", id),
        ("redirect_uri", &redirect),
        ("response_type", "code"),
        ("scope", SCOPE),
        ("access_type", "offline"),
        ("prompt", "consent"),
    ]).into_diagnostic()?;
    eprintln!("consent at: {url}");
    Command::new("xdg-open").arg(url.as_str()).spawn().into_diagnostic()?;
    let params: BTreeMap<String, String> = loop {
        let (mut stream, _) = listener.accept().into_diagnostic()?;
        stream.set_read_timeout(Some(Duration::from_secs(5))).into_diagnostic()?; // browsers preconnect sockets they never send on
        let mut line = String::new();
        if BufReader::new(&stream).read_line(&mut line).is_err() {
            continue; // such a preconnect
        }
        let Some(target) = line.split_whitespace().nth(1) else { continue };
        let params: BTreeMap<String, String> = Url::parse(&format!("http://localhost{target}")).into_diagnostic()?.query_pairs().into_owned().collect();
        if !(params.contains_key("code") || params.contains_key("error")) {
            stream.write_all(b"HTTP/1.1 404 Not Found\r\ncontent-length: 0\r\n\r\n").into_diagnostic()?;
            continue;
        }
        stream.write_all(b"HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\n\r\ncalendar_shift: done, this tab can close\n").into_diagnostic()?;
        break params;
    };
    let code = params.get("code").ok_or_else(|| miette!("consent refused: {params:?}"))?;
    let resp: Value = http
        .post(TOKEN_URL)
        .form(&[("code", code.as_str()), ("client_id", id), ("client_secret", secret), ("redirect_uri", &redirect), ("grant_type", "authorization_code")])
        .send().into_diagnostic()?
        .json().into_diagnostic()?;
    Ok(str_of(&resp["refresh_token"]).map_err(|_| miette!("code exchange: {resp}"))?.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recurrence_moves_with_series() {
        let paris = TimeZone::get("Europe/Paris").unwrap();
        let rec = vec![
            "RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20261231T225959Z".to_owned(),
            "EXDATE;TZID=Europe/Paris:20261130T083000,20261207T083000".to_owned(),
            "EXDATE:20261214T073000Z".to_owned(),
        ];
        assert_eq!(shift_recurrence(&rec, SignedDuration::from_hours(1), &paris).unwrap(), vec![
            "RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20261231T235959Z",
            "EXDATE;TZID=Europe/Paris:20261130T093000,20261207T093000",
            "EXDATE:20261214T083000Z",
        ]);
        assert!(shift_recurrence(&["EXDATE;VALUE=DATE:20261130".to_owned()], SignedDuration::from_hours(1), &paris).is_err());
        assert_eq!(set_rrule_param("RRULE:FREQ=DAILY;COUNT=10", "COUNT", None), "RRULE:FREQ=DAILY");
        assert_eq!(set_rrule_param("RRULE:FREQ=DAILY;COUNT=10", "UNTIL", Some("20261130")), "RRULE:FREQ=DAILY;COUNT=10;UNTIL=20261130");
    }
}
