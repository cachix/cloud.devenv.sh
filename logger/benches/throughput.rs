use criterion::{BenchmarkId, Criterion, Throughput, black_box, criterion_group, criterion_main};
use devenv_logger::{AppState, Log, create_app, create_db};
use futures_util::StreamExt;
use http_body_util::BodyExt;
use hyperlocal::UnixClientExt;
use std::sync::Arc;
use std::time::Duration;
use time::format_description::well_known::Rfc3339;
use tokio::net::UnixListener;
use tokio::sync::mpsc;
use uuid::Uuid;

fn generate_log_messages(num_messages: u64) -> Vec<String> {
    let mut messages = Vec::with_capacity(num_messages as usize);
    let base_timestamp = time::OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap()
        .to_string();

    for i in 1..=num_messages {
        let log = Log {
            timestamp: base_timestamp.clone(),
            message: format!("Benchmark message #{}", i),
            level: "INFO".to_string(),
        };
        let json_line = format!("{}\n", serde_json::to_string(&log).unwrap());
        messages.push(json_line);
    }

    messages
}

async fn stream_pregenerated_logs(
    messages: Vec<String>,
    socket_path: &str,
) -> Result<Duration, Box<dyn std::error::Error>> {
    let session_uuid = Uuid::now_v7();
    let url: hyper::Uri = hyperlocal::Uri::new(socket_path, &format!("/{}", session_uuid)).into();

    let (tx, rx) = mpsc::channel::<Result<bytes::Bytes, std::io::Error>>(10000);

    let message_count = messages.len();
    let start_time = std::time::Instant::now();

    // Producer task - stream pre-generated messages as fast as possible
    let producer_handle = tokio::spawn(async move {
        let producer_start = std::time::Instant::now();
        for message in messages {
            if tx.send(Ok(bytes::Bytes::from(message))).await.is_err() {
                break;
            }
        }
        // Signal completion by dropping the sender
        drop(tx);
        eprintln!(
            "Producer sent {} messages in {:?}",
            message_count,
            producer_start.elapsed()
        );
    });

    // Create a stream that will complete when all messages are consumed
    let body = http_body_util::StreamBody::new(
        tokio_stream::wrappers::ReceiverStream::new(rx)
            .map(|result| result.map(hyper::body::Frame::data)),
    );
    let body = http_body_util::combinators::BoxBody::new(body);

    let client = hyper_util::client::legacy::Client::unix();

    let req = hyper::Request::builder()
        .method("POST")
        .uri(url)
        .header("Content-Type", "application/x-ndjson")
        .body(body)?;

    let request_start = std::time::Instant::now();
    let response = client.request(req).await?;
    eprintln!(
        "Request sent and initial response received in {:?}",
        request_start.elapsed()
    );

    // Wait for the producer to finish sending all messages
    producer_handle.await?;

    // Ensure the response is fully consumed
    let consume_start = std::time::Instant::now();
    let body = response.into_body();
    let _ = body.collect().await?.to_bytes();
    eprintln!("Response body consumed in {:?}", consume_start.elapsed());

    let total_elapsed = start_time.elapsed();
    eprintln!(
        "Total time for {} messages: {:?}",
        message_count, total_elapsed
    );

    Ok(total_elapsed)
}

fn benchmark_throughput(c: &mut Criterion) {
    let rt = tokio::runtime::Runtime::new().unwrap();

    // Setup server once for all benchmarks
    let (socket_path, server_handle) = rt.block_on(async {
        let temp_dir = format!("/tmp/logger-bench-{}", uuid::Uuid::new_v4());
        let socket_path = format!("{}/socket", temp_dir);

        std::fs::create_dir_all(&temp_dir).unwrap();

        let db = create_db(&temp_dir).await.unwrap();
        let app_state = Arc::new(AppState { db });
        let app = create_app(app_state);

        // Start server on Unix socket
        let listener = UnixListener::bind(&socket_path).unwrap();

        // Spawn the server
        let server_handle = tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });

        // Give the server a moment to start
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        (socket_path, server_handle)
    });

    let mut group = c.benchmark_group("logger");

    group.sample_size(10);
    group.measurement_time(Duration::from_secs(15));

    for &num_messages in &[100, 10_000, 1_000_000] {
        group.throughput(Throughput::Elements(num_messages));

        // Pre-generate messages outside the benchmark
        let messages = generate_log_messages(num_messages);

        group.bench_with_input(
            BenchmarkId::new("throughput", num_messages),
            &(messages, &socket_path),
            |b, (messages, socket_path)| {
                b.iter(|| {
                    rt.block_on(async {
                        black_box(
                            stream_pregenerated_logs(messages.clone(), socket_path)
                                .await
                                .unwrap(),
                        )
                    })
                })
            },
        );
    }
    group.finish();

    // Cleanup
    server_handle.abort();
    let temp_dir = socket_path.rsplit('/').nth(1).unwrap();
    let _ = std::fs::remove_dir_all(format!("/tmp/{}", temp_dir));
}

criterion_group!(benches, benchmark_throughput);
criterion_main!(benches);
