#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[dependencies]
reqwest = { version = "0.12", features = ["json"] }
serde = { version = "1", features = ["derive"] }
tokio = { version = "1", features = ["full"] }
twitch_api = { version = "0.7", features = ["client", "helix", "reqwest"] }
---

use std::time::Duration;

const POLL_INTERVAL: Duration = Duration::from_secs(30);

enum Platform {
	Twitch(String),
	YouTube(String),
}

fn parse_url(url: &str) -> Platform {
	if url.contains("twitch.tv") {
		let channel = url
			.trim_end_matches('/')
			.rsplit('/')
			.next()
			.expect("no channel name in twitch URL");
		Platform::Twitch(channel.to_string())
	} else if url.contains("youtube.com") || url.contains("youtu.be") {
		Platform::YouTube(url.to_string())
	} else {
		panic!("unsupported platform: {url}");
	}
}

fn env_or_panic(key: &str) -> String {
	std::env::var(key).unwrap_or_else(|_| panic!("{key} not set"))
}

struct TwitchCtx {
	client: twitch_api::HelixClient<'static, reqwest::Client>,
	token: twitch_api::twitch_oauth2::AppAccessToken,
}

impl TwitchCtx {
	async fn new() -> Self {
		let http = reqwest::Client::builder()
			.redirect(reqwest::redirect::Policy::none())
			.build()
			.expect("failed to build http client");
		let token = twitch_api::twitch_oauth2::AppAccessToken::get_app_access_token(
			&http,
			env_or_panic("TWITCH_CLIENT_ID").into(),
			env_or_panic("TWITCH_CLIENT_SECRET").into(),
			vec![],
		)
		.await
		.expect("failed to get twitch app access token");
		Self {
			client: twitch_api::HelixClient::default(),
			token,
		}
	}

	async fn viewer_count(&self, channel: &str) -> u64 {
		use twitch_api::helix::streams::GetStreamsRequest;
		let logins: &[&str] = &[channel];
		let req = GetStreamsRequest::user_logins(logins);
		let resp = self
			.client
			.req_get(req, &self.token)
			.await
			.expect("twitch streams request failed");
		resp.data.first().map(|s| s.viewer_count).unwrap_or(0) as u64
	}
}

async fn youtube_video_id(http: &reqwest::Client, url: &str, api_key: &str) -> String {
	if url.contains("watch?v=") {
		return url.split("watch?v=").nth(1).unwrap().split('&').next().unwrap().to_string();
	}
	if url.contains("youtu.be/") {
		return url.split("youtu.be/").nth(1).unwrap().split('?').next().unwrap().to_string();
	}
	if url.contains("youtube.com/live/") {
		return url.split("/live/").nth(1).unwrap().split('?').next().unwrap().to_string();
	}

	// Channel URL — resolve to live video
	let channel_id = if url.contains("/channel/") {
		url.split("/channel/").nth(1).unwrap().split('/').next().unwrap().to_string()
	} else if url.contains("/@") {
		let handle = url.split("/@").nth(1).unwrap().split('/').next().unwrap();
		#[derive(serde::Deserialize)]
		struct Item { id: String }
		#[derive(serde::Deserialize)]
		struct Resp { items: Vec<Item> }
		let resp: Resp = http
			.get("https://www.googleapis.com/youtube/v3/channels")
			.query(&[("part", "id"), ("forHandle", handle), ("key", api_key)])
			.send().await.expect("youtube channel lookup failed")
			.json().await.expect("youtube channel parse failed");
		resp.items.first().expect("youtube channel not found").id.clone()
	} else {
		panic!("cannot determine youtube video ID from: {url}");
	};

	#[derive(serde::Deserialize)]
	struct SearchId { #[serde(rename = "videoId")] video_id: Option<String> }
	#[derive(serde::Deserialize)]
	struct SearchItem { id: SearchId }
	#[derive(serde::Deserialize)]
	struct SearchResp { items: Vec<SearchItem> }

	let resp: SearchResp = http
		.get("https://www.googleapis.com/youtube/v3/search")
		.query(&[
			("part", "id"), ("channelId", &channel_id),
			("type", "video"), ("eventType", "live"), ("key", api_key),
		])
		.send().await.expect("youtube search failed")
		.json().await.expect("youtube search parse failed");

	resp.items.first()
		.and_then(|i| i.id.video_id.clone())
		.expect("no live stream found for this channel")
}

async fn youtube_viewer_count(http: &reqwest::Client, video_id: &str, api_key: &str) -> u64 {
	#[derive(serde::Deserialize)]
	struct LiveDetails { #[serde(rename = "concurrentViewers")] concurrent_viewers: Option<String> }
	#[derive(serde::Deserialize)]
	struct VideoItem { #[serde(rename = "liveStreamingDetails")] live_streaming_details: Option<LiveDetails> }
	#[derive(serde::Deserialize)]
	struct VideoResp { items: Vec<VideoItem> }

	let resp: VideoResp = http
		.get("https://www.googleapis.com/youtube/v3/videos")
		.query(&[("part", "liveStreamingDetails"), ("id", video_id), ("key", api_key)])
		.send().await.expect("youtube video request failed")
		.json().await.expect("youtube video parse failed");

	resp.items.first()
		.and_then(|i| i.live_streaming_details.as_ref())
		.and_then(|d| d.concurrent_viewers.as_ref())
		.and_then(|v| v.parse().ok())
		.unwrap_or(0)
}

fn notify(msg: &str) {
	let _ = std::process::Command::new("notify-send")
		.args(["-t", "5000", msg])
		.status();
}

#[tokio::main]
async fn main() {
	let url = std::env::args().nth(1).expect("usage: notify_new_viewer <stream_url>");
	let platform = parse_url(&url);
	let http = reqwest::Client::new();

	// Resolve platform-specific state once
	let twitch_ctx;
	let yt_video_id;
	let yt_api_key;
	match &platform {
		Platform::Twitch(_) => {
			twitch_ctx = Some(TwitchCtx::new().await);
			yt_video_id = String::new();
			yt_api_key = String::new();
		}
		Platform::YouTube(url) => {
			yt_api_key = env_or_panic("YOUTUBE_API_KEY");
			yt_video_id = youtube_video_id(&http, url, &yt_api_key).await;
			twitch_ctx = None;
		}
	}

	let mut prev_count: Option<u64> = None;
	loop {
		let count = match &platform {
			Platform::Twitch(channel) => twitch_ctx.as_ref().unwrap().viewer_count(channel).await,
			Platform::YouTube(_) => youtube_viewer_count(&http, &yt_video_id, &yt_api_key).await,
		};

		match prev_count {
			Some(prev) if count > prev => {
				let diff = count - prev;
				let word = if diff == 1 { "viewer" } else { "viewers" };
				let msg = format!("+{diff} {word} ({count} total)");
				println!("{msg}");
				notify(&msg);
			}
			Some(prev) if count < prev => {
				println!("-{} viewers ({count} total)", prev - count);
			}
			None => {
				let msg = format!("Watching stream: {count} viewers");
				println!("{msg}");
				notify(&msg);
			}
			_ => {}
		}

		prev_count = Some(count);
		tokio::time::sleep(POLL_INTERVAL).await;
	}
}
