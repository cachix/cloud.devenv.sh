use axum::{
    BoxError, Router,
    extract::Path,
    response::{
        IntoResponse, Result,
        sse::{Event, KeepAlive, Sse},
    },
    routing::{get, post},
};
use axum_extra::json_lines::JsonLines;
use bytes::Bytes;
use futures_util::stream::{Stream, StreamExt};
use serde::{Deserialize, Serialize};
use slatedb::Db;
use std::pin::Pin;
use std::sync::Arc;
use tower_http::cors::{self, CorsLayer};
use uuid::Uuid;

use crate::Log;
use crate::stream;

pub struct AppState {
    pub db: Arc<Db>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LogWithLine {
    message: String,
    timestamp: String,
    level: String,
    line: u64,
}

pub fn create_app(state: Arc<AppState>) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(cors::Any)
        .allow_methods(cors::Any)
        .allow_headers(cors::Any)
        .expose_headers([
            axum::http::header::CONTENT_TYPE,
            axum::http::header::CACHE_CONTROL,
        ])
        .max_age(std::time::Duration::from_secs(3600));

    Router::new()
        .route("/{uuid}", post(post_logs))
        .route("/{uuid}", get(get_logs))
        .layer(cors)
        .with_state(state)
}

async fn post_logs(
    state: axum::extract::State<Arc<AppState>>,
    Path(uuid): axum::extract::Path<Uuid>,
    mut stream: JsonLines<Log>,
) {
    eprintln!("Receiving logs for UUID: {uuid}");

    let db = &state.db;
    let mut line_counter = 0;
    let start_time = std::time::Instant::now();

    while let Some(log_entry) = stream.next().await {
        match log_entry {
            Ok(log) => {
                line_counter += 1;
                let log_with_line = LogWithLine {
                    message: log.message,
                    timestamp: log.timestamp,
                    level: log.level,
                    line: line_counter,
                };

                let key = stream::LogLineKey::from_parts(uuid, line_counter);
                let json_log = serde_json::to_vec(&log_with_line).expect("Failed to serialize log");

                // Use put_with_options with await_durable=false for better throughput
                let put_options = slatedb::config::PutOptions::default();
                let write_options = slatedb::config::WriteOptions {
                    await_durable: false,
                };

                let write_start = std::time::Instant::now();
                if let Err(e) = db
                    .put_with_options(&key.as_bytes(), &json_log, &put_options, &write_options)
                    .await
                {
                    eprintln!("Failed to write log: {e:?}");
                }
                let write_elapsed = write_start.elapsed();
                if write_elapsed > std::time::Duration::from_millis(10) {
                    eprintln!("Slow write: {:?}", write_elapsed);
                }
            }
            Err(err) => eprintln!("Failed to parse log: {err:?}"),
        }
    }

    let elapsed = start_time.elapsed();
    eprintln!(
        "Received {} logs in {:?} ({:.0} logs/sec)",
        line_counter,
        elapsed,
        line_counter as f64 / elapsed.as_secs_f64()
    );
}

async fn get_logs(
    state: axum::extract::State<Arc<AppState>>,
    Path(uuid): axum::extract::Path<Uuid>,
) -> axum::response::Response {
    let db = Arc::clone(&state.db);

    let base_stream: Pin<Box<dyn Stream<Item = Result<(Bytes, Bytes), BoxError>> + Send>> =
        stream::DbFetcher::new(db, uuid).await.into_stream();

    let stream = base_stream.filter_map(|log| async move {
        log.ok().map(|(_, value)| {
            Ok::<Event, BoxError>(Event::default().data(String::from_utf8_lossy(&value)))
        })
    });

    let ready_event = futures_util::stream::once(async {
        Ok::<Event, BoxError>(Event::default().event("ready").data("{}"))
    });

    let stream = ready_event.chain(stream);

    let keep_alive = KeepAlive::default()
        .interval(std::time::Duration::from_secs(15))
        .text("keep-alive-text");

    let sse = Sse::new(stream).keep_alive(keep_alive);
    let mut response = sse.into_response();

    let headers = response.headers_mut();
    headers.insert("Access-Control-Allow-Origin", "*".parse().unwrap());
    headers.insert(
        "Access-Control-Allow-Methods",
        "GET, POST, OPTIONS".parse().unwrap(),
    );
    headers.insert("Access-Control-Allow-Headers", "*".parse().unwrap());
    headers.insert(
        "Access-Control-Expose-Headers",
        "Content-Type, Cache-Control".parse().unwrap(),
    );
    headers.insert("Cache-Control", "no-cache".parse().unwrap());
    headers.insert("Content-Type", "text/event-stream".parse().unwrap());

    response
}
