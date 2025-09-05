use reqwest::Client;
use serde_json::json;
use std::time::Duration;
use time::format_description::well_known::Rfc3339;
use tokio::sync::mpsc;
use tokio::time::interval;
use uuid::Uuid;

fn generate_log_entry(i: u64) -> String {
    let log_entry = json!({
        "timestamp": time::OffsetDateTime::now_utc().format(&Rfc3339).unwrap().to_string(),
        "line": i,
        "message": format!("Message on line {}", i),
    });
    format!("{log_entry}\n")
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new();
    let session_uuid = Uuid::now_v7();
    println!("Session UUID: {session_uuid}");

    let url = format!("http://localhost:3000/{session_uuid}");

    // Create a channel to send log entries
    let (tx, rx) = mpsc::channel::<Result<String, String>>(100);

    // Spawn a task to generate log entries
    tokio::spawn(async move {
        let mut interval = interval(Duration::from_secs(1));
        let mut i = 0;
        loop {
            interval.tick().await;
            let log_entry = generate_log_entry(i);
            if tx.send(Ok(log_entry)).await.is_err() {
                break;
            }
            i += 1;
        }
    });

    // Create a stream from the receiver
    let stream = tokio_stream::wrappers::ReceiverStream::new(rx);

    // Send the stream as the request body
    let response = client
        .post(&url)
        .header("Content-Type", "application/x-ndjson")
        .body(reqwest::Body::wrap_stream(stream))
        .send()
        .await?;

    // TODO: in our test, we never get to this point.
    let _ = response.bytes().await?;

    Ok(())
}
