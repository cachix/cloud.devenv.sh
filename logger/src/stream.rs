use axum::BoxError;
use bytes::Bytes;
use futures_util::Stream;
use slatedb::Db;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;
use tokio::time::sleep;
use uuid::Uuid;

pub(crate) struct LogLineKey {
    uuid: Uuid,
    log_line: AtomicU64,
}

impl LogLineKey {
    pub fn from_parts(uuid: Uuid, log_line: u64) -> Self {
        Self {
            uuid,
            log_line: AtomicU64::new(log_line),
        }
    }

    pub fn increment(&self) {
        // Use Relaxed ordering for better performance - sequential consistency
        // is not needed for a simple counter increment
        self.log_line.fetch_add(1, Ordering::Relaxed);
    }

    pub fn log_line(&self) -> u64 {
        // Acquire ordering is sufficient here - we only need to ensure this load
        // observes prior stores
        self.log_line.load(Ordering::Acquire)
    }

    fn format_key(&self, log_line: u64) -> String {
        format!("{}-{:016x}", self.uuid, log_line)
    }

    pub fn as_bytes(&self) -> Bytes {
        self.to_string().into()
    }

    pub fn range_max(&self) -> Bytes {
        self.format_key(u64::MAX).into()
    }
}

impl std::fmt::Display for LogLineKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.format_key(self.log_line()))
    }
}

pub(crate) struct DbFetcher {
    db: Arc<Db>,
    uuid: Uuid,
}

impl DbFetcher {
    pub async fn new(db: Arc<Db>, uuid: Uuid) -> Self {
        Self { db, uuid }
    }

    /// Convert the DbFetcher into a stream that yields log entries.
    ///
    /// The stream will yield log entries as they are written to the database.
    pub fn into_stream(
        self,
    ) -> Pin<Box<dyn Stream<Item = Result<(Bytes, Bytes), BoxError>> + Send + 'static>> {
        Box::pin(async_stream::stream! {
            let key = Arc::new(LogLineKey::from_parts(self.uuid, 0));

            loop {
                match self.db.scan(key.as_bytes()..key.range_max()).await {
                    Ok(mut db_iter) => {
                        let mut items_found = false;

                        while let Ok(Some(item)) = db_iter.next().await {
                            items_found = true;
                            key.increment();
                            yield Ok((item.key, item.value));
                        }

                        if !items_found {
                            sleep(Duration::from_millis(50)).await;
                        }
                    },
                    Err(e) => {
                        yield Err(e.into());
                        sleep(Duration::from_millis(50)).await;
                    }
                }
            }
        })
    }
}
