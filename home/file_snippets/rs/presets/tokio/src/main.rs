use anyhow::Result;

#[tokio::main]
async fn main() -> Result<()> {
	let (tx, mut rx) = tokio::sync::mpsc::channel(32);
	tokio::spawn(async move {
		tx.send("world").await.unwrap();
	});

	let msg = rx.recv().await.unwrap();
	println!("Hello, {}!", msg);

	Ok(())
}
