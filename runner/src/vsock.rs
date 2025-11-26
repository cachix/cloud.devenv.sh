use crate::protocol::{CONFIG_VSOCK_PORT, JobConfig, VsockGuestMessage, VsockHostMessage};
use backon::{ExponentialBuilder, Retryable};
use eyre::{Result, WrapErr};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::Value;
use std::collections::HashMap;
use std::io::{self, Write};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{Mutex, Notify, mpsc};
use tokio_vsock::{VsockAddr, VsockStream};
use tracing::{error, info};

/// The CID for the host.
pub const HOST_CID: u32 = tokio_vsock::VMADDR_CID_HOST;

/// Encapsulates job reporting over vsock connection
pub struct JobReporter {
    stream: VsockStream,
    job_id: uuid::Uuid,
}

impl JobReporter {
    /// Create a new job reporter from an existing vsock stream
    pub fn new(stream: VsockStream, job_id: uuid::Uuid) -> Self {
        Self { stream, job_id }
    }

    /// Report job completion status to the host
    pub async fn report_complete(&mut self, success: bool) -> Result<()> {
        let complete = VsockGuestMessage::Complete {
            id: self.job_id,
            success,
        };
        self.stream.write_message(&complete).await?;
        Ok(())
    }

    /// Send a log message to the host
    pub async fn send_log(
        &mut self,
        level: String,
        target: String,
        message: String,
        fields: std::collections::HashMap<String, String>,
    ) -> Result<()> {
        let log = VsockGuestMessage::Log {
            id: self.job_id,
            level,
            target,
            message,
            fields,
        };
        self.stream.write_message(&log).await?;
        Ok(())
    }
}

/// Structured log entry to be sent through vsock
#[derive(Serialize, Deserialize)]
pub struct LogEntry {
    pub level: String,
    pub target: String,
    pub message: String,
    pub fields: HashMap<String, String>,
}

/// A writer that sends logs through vsock connection using a buffered channel
#[derive(Clone)]
pub struct VsockWriter {
    log_sender: mpsc::Sender<LogEntry>,
}

impl VsockWriter {
    pub fn new(reporter: Arc<Mutex<JobReporter>>) -> Self {
        // Create a channel for buffering log entries
        let (log_sender, mut log_receiver) = mpsc::channel::<LogEntry>(100);

        // Spawn a single task to handle all log sending
        tokio::spawn(async move {
            while let Some(log_entry) = log_receiver.recv().await {
                let mut reporter_guard = reporter.lock().await;
                if let Err(e) = reporter_guard
                    .send_log(
                        log_entry.level,
                        log_entry.target,
                        log_entry.message,
                        log_entry.fields,
                    )
                    .await
                {
                    eprintln!("Failed to send log via vsock: {}", e);
                }
            }
        });

        Self { log_sender }
    }
}

impl Write for VsockWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        // Parse the JSON log line
        if let Ok(json_str) = std::str::from_utf8(buf) {
            if let Ok(json_value) = serde_json::from_str::<Value>(json_str) {
                // Extract fields from JSON
                let level = json_value
                    .get("level")
                    .and_then(|v| v.as_str())
                    .unwrap_or("INFO")
                    .to_string();

                let target = json_value
                    .get("target")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                let message = json_value
                    .get("fields")
                    .and_then(|f| f.get("message"))
                    .and_then(|v| v.as_str())
                    .or_else(|| json_value.get("message").and_then(|v| v.as_str()))
                    .unwrap_or("")
                    .to_string();

                // Extract other fields
                let mut fields = HashMap::new();
                if let Some(json_fields) = json_value.get("fields").and_then(|v| v.as_object()) {
                    for (key, value) in json_fields {
                        if key != "message" {
                            fields.insert(key.clone(), value.to_string());
                        }
                    }
                }

                // Send log entry through the channel (non-blocking)
                let log_entry = LogEntry {
                    level,
                    target,
                    message,
                    fields,
                };

                // Use try_send to avoid blocking in the Write trait
                if let Err(e) = self.log_sender.try_send(log_entry) {
                    eprintln!("Log channel full or closed: {}", e);
                }
            }
        }

        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

/// Trait for reading/writing messages over different stream types
#[async_trait::async_trait]
trait MessageStream: AsyncReadExt + AsyncWriteExt + Unpin {
    async fn read_message<T: DeserializeOwned + Send>(&mut self) -> Result<T> {
        // Read message length (u32)
        let mut len_buf = [0u8; 4];
        self.read_exact(&mut len_buf).await?;
        let len = u32::from_le_bytes(len_buf) as usize;

        // Read and deserialize the message
        let mut buf = vec![0u8; len];
        self.read_exact(&mut buf).await?;
        serde_json::from_slice(&buf).wrap_err("Failed to deserialize message")
    }

    async fn write_message<T: Serialize + Sync>(&mut self, message: &T) -> Result<()> {
        let data = serde_json::to_vec(message).wrap_err("Failed to serialize message")?;
        let len = data.len() as u32;
        self.write_all(&len.to_le_bytes()).await?;
        self.write_all(&data).await?;
        Ok(())
    }
}

// Implement MessageStream for VsockStream
#[async_trait::async_trait]
impl MessageStream for VsockStream {}

// Implement MessageStream for UnixStream
#[async_trait::async_trait]
impl MessageStream for UnixStream {}

/// Start a UNIX socket server on the Linux host to send job configuration to the guest
/// This is used with Cloud Hypervisor which requires UNIX sockets for guest-to-host communication
pub async fn start_unix_config_server(
    vsock_socket_path: PathBuf,
    job_config: JobConfig,
    job_result: Option<Arc<tokio::sync::Mutex<Option<bool>>>>,
    log_sender: mpsc::Sender<String>,
) -> Result<()> {
    // Construct the UNIX socket path as per Cloud Hypervisor documentation
    let socket_path = PathBuf::from(format!(
        "{}_{}",
        vsock_socket_path.display(),
        CONFIG_VSOCK_PORT
    ));

    // Remove existing socket file if it exists
    if socket_path.exists() {
        std::fs::remove_file(&socket_path)?;
    }

    let listener = UnixListener::bind(&socket_path)?;
    info!("UNIX socket server on {:?}", socket_path);

    // Create a notification channel to signal when the server should shut down
    let shutdown_notify = Arc::new(Notify::new());

    loop {
        let shutdown_notify_clone = shutdown_notify.clone();

        tokio::select! {
            // Wait for new connections
            accept_result = listener.accept() => {
                match accept_result {
                    Ok((mut stream, _)) => {
                        let job_config = job_config.clone();
                        let job_result = job_result.clone();
                        let shutdown_notify_task = shutdown_notify.clone();
                        let log_sender = log_sender.clone();
                        tokio::spawn(async move {
                            if let Err(e) =
                                handle_guest_connection(&mut stream, job_config, job_result, shutdown_notify_task, log_sender).await
                            {
                                error!("Error handling guest connection: {:?}", e);
                            }
                        });
                    }
                    Err(e) => error!("Failed to accept connection: {:?}", e),
                }
            }
            // Wait for shutdown signal
            _ = shutdown_notify_clone.notified() => {
                info!("Vsock server shutting down after job completion");
                break;
            }
        }
    }

    // Clean up the socket file
    if socket_path.exists() {
        std::fs::remove_file(&socket_path)?;
    }

    tracing::info!("Vsock server task completed");
    Ok(())
}

/// Handle a guest connection and send the job configuration
pub async fn handle_guest_connection(
    stream: &mut UnixStream,
    job_config: JobConfig,
    job_result_state: Option<Arc<tokio::sync::Mutex<Option<bool>>>>,
    shutdown_notify: Arc<Notify>,
    log_sender: mpsc::Sender<String>,
) -> Result<()> {
    let job_id = job_config.id;

    // Send the job configuration
    let message = VsockHostMessage::JobConfig(job_config);
    stream
        .write_message(&message)
        .await
        .wrap_err("Failed to send job configuration to guest")?;

    // Wait for acknowledgement
    let response: VsockGuestMessage = stream
        .read_message()
        .await
        .wrap_err("Failed to read acknowledge from guest")?;

    match response {
        VsockGuestMessage::Ready { id } if id == job_id => {
            info!("Guest ready to execute job {}", id);
        }
        VsockGuestMessage::Ready { id } => {
            return Err(eyre::eyre!(
                "Guest ready with wrong job ID: expected {}, got {}",
                job_id,
                id
            ));
        }
        VsockGuestMessage::Complete { .. } => {
            return Err(eyre::eyre!(
                "Unexpected Complete message during initial handshake"
            ));
        }
        VsockGuestMessage::Log { .. } => {
            return Err(eyre::eyre!(
                "Unexpected Log message during initial handshake"
            ));
        }
    }

    // Keep the connection alive to receive job result
    let mut received_result = None;
    loop {
        match stream.read_message::<VsockGuestMessage>().await {
            Ok(VsockGuestMessage::Complete { id, success }) if id == job_id => {
                info!(
                    "Job {} completed with status: {}",
                    id,
                    if success { "success" } else { "failure" }
                );
                received_result = Some(success);
                break;
            }
            Ok(VsockGuestMessage::Complete { id, .. }) => {
                error!(
                    "Received complete message for wrong job ID: expected {}, got {}",
                    job_id, id
                );
            }
            Ok(VsockGuestMessage::Log {
                id,
                level,
                target,
                message,
                fields,
            }) if id == job_id => {
                // Create a structured log message
                let log_entry = LogEntry {
                    level: level.clone(),
                    target: target.clone(),
                    message: message.clone(),
                    fields: fields.clone(),
                };

                // Send as JSON to preserve structure
                match serde_json::to_string(&log_entry) {
                    Ok(json_log) => {
                        if let Err(e) = log_sender.send(json_log).await {
                            error!("Failed to send log message: {}", e);
                        }
                    }
                    Err(e) => {
                        error!("Failed to serialize log entry: {}", e);
                    }
                }
            }
            Ok(VsockGuestMessage::Log { id, .. }) => {
                error!(
                    "Received log message for wrong job ID: expected {}, got {}",
                    job_id, id
                );
            }
            Ok(msg) => info!(
                "Received unexpected message from guest for job {}: {:?}",
                job_id, msg
            ),
            Err(_) => {
                error!(
                    "Lost connection to guest for job {} before receiving complete message",
                    job_id
                );
                break;
            }
        }
    }

    // Store the job result in the shared state if provided
    if let (Some(success), Some(result_state)) = (received_result, job_result_state) {
        let mut result_guard = result_state.lock().await;
        *result_guard = Some(success);
        info!(
            "Job {} result stored: {}",
            job_id,
            if success { "success" } else { "failure" }
        );
    }

    // Signal the server to shut down after job completion
    if received_result.is_some() {
        // Notify the vsock server to shut down
        shutdown_notify.notify_one();
    }

    Ok(())
}

/// Connect to the vsock server from the guest to receive job configuration
pub async fn receive_config_from_host() -> Result<(JobConfig, JobReporter)> {
    let addr = VsockAddr::new(tokio_vsock::VMADDR_CID_HOST, CONFIG_VSOCK_PORT);

    // Connect with exponential backoff retry
    let mut stream = (|| async { VsockStream::connect(addr).await })
        .retry(
            ExponentialBuilder::default()
                .with_min_delay(Duration::from_millis(100))
                .with_max_delay(Duration::from_secs(5))
                .with_max_times(10),
        )
        .when(|_| true) // Retry on all errors
        .notify(|err, dur| {
            info!("Failed to connect to vsock: {}. Retrying in {:?}", err, dur);
        })
        .await
        .wrap_err("Failed to connect to vsock server after 10 retries")?;

    // Read the job configuration
    let message: VsockHostMessage = stream
        .read_message()
        .await
        .wrap_err("Failed to read job configuration from host")?;

    match message {
        VsockHostMessage::JobConfig(config) => {
            let job_id = config.id;
            // Send ready message
            let ready = VsockGuestMessage::Ready { id: job_id };
            stream.write_message(&ready).await?;

            // Create job reporter with the established connection
            let reporter = JobReporter::new(stream, job_id);
            Ok((config, reporter))
        }
    }
}
