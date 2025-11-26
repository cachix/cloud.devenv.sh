use backon::{ExponentialBuilder, Retryable};
use clap::Parser;
use devenv_logger::Log;
use devenv_runner::client::{WebSocketClient, WebSocketError};
use devenv_runner::config::VmConfig;
use devenv_runner::job_manager::{JobManager, JobStatusEvent};
use devenv_runner::protocol::{
    ClientMessage, CompletionStatus, JobConfig, JobStatus, RunnerMetrics, ServerMessage,
};
use devenv_runner::resource_manager::ResourceManager;
use devenv_runner::vm_manager::{VmCompletionEvent, VmManager};
use eyre::Result;
use futures_util::{Stream, StreamExt};
use reqwest::{Body, Client as HttpClient};
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;
use tokio::signal::unix::{SignalKind, signal};
use tokio::sync::{mpsc, oneshot};
use tokio_stream::wrappers::ReceiverStream;
use tokio_tungstenite::tungstenite::http::Uri;
use tracing_subscriber::prelude::*;
use uuid::Uuid;

// Constants
const LOG_CHANNEL_BUFFER_SIZE: usize = 100;

/// Type alias for the WebSocket read stream
type WsReadStream = Pin<Box<dyn Stream<Item = Result<ServerMessage, WebSocketError>> + Send>>;

/// Reconnect to WebSocket server with exponential backoff
async fn reconnect_websocket(ws_url: Uri) -> Result<(WebSocketClient, WsReadStream)> {
    let (client, read) = (|| async { WebSocketClient::new(ws_url.clone(), None).await })
        .retry(
            ExponentialBuilder::default()
                .with_min_delay(Duration::from_secs(1))
                .with_max_delay(Duration::from_secs(60))
                .with_max_times(usize::MAX),
        ) // Retry indefinitely
        .when(|_: &_| true) // Retry on all errors
        .notify(|err, dur| {
            tracing::error!(
                "Failed to connect to WebSocket: {}. Retrying in {:?}",
                err,
                dur
            );
        })
        .await
        .map_err(|e| eyre::eyre!("Failed to connect to WebSocket after all retries: {}", e))?;

    Ok((client, Box::pin(read)))
}

/// Checks if the runner has enough capacity to handle more jobs, and if so, requests one.
///
/// Requires at least 1 CPU and some available memory.
async fn check_capacity_and_request_job(
    client: &mut WebSocketClient,
    resource_manager: &ResourceManager,
) -> Result<()> {
    if resource_manager.has_minimal_capacity().await {
        tracing::debug!(
            "Requesting job with available capacity - {}",
            resource_manager.resource_summary().await
        );
        client.send_message(ClientMessage::RequestJob, None).await?
    }

    Ok(())
}

/// Sets up a log streaming infrastructure for a job.
///
/// This function creates a logging channel and spawns a background task that:
/// 1. Sends an initial log message about VM startup
/// 2. Converts log messages to NDJSON format
/// 3. Sends all logs via a streaming HTTP request
///
/// Returns a channel sender that can be used to send additional log messages.
async fn setup_log_stream(
    http_client: HttpClient,
    log_url: impl AsRef<str> + Send + 'static,
    job_id: Uuid,
    cpu_count: usize,
    memory_mb: u64,
) -> mpsc::Sender<String> {
    // Create stream for logs with buffer
    let (log_sender, log_receiver) = mpsc::channel::<String>(LOG_CHANNEL_BUFFER_SIZE);
    let log_sender_clone = log_sender.clone();

    // Start a background task that will handle the continuous log stream
    tokio::spawn(async move {
        // Initial log message as structured log
        let log_entry = devenv_runner::vsock::LogEntry {
            level: "INFO".to_string(),
            target: "runner".to_string(),
            message: format!(
                "Job {job_id} claimed, starting VM with {cpu_count} CPUs and {memory_mb}MB RAM"
            ),
            fields: std::collections::HashMap::new(),
        };

        // Send initial log message
        if let Ok(json_log) = serde_json::to_string(&log_entry) {
            if let Err(e) = log_sender_clone.send(json_log).await {
                tracing::error!("Failed to send initial log message: {}", e);
            }
        }

        // Transform log messages into NDJSON
        let log_stream = ReceiverStream::new(log_receiver).map(|message| {
            // Try to parse as structured log first
            let log = if let Ok(log_entry) =
                serde_json::from_str::<devenv_runner::vsock::LogEntry>(&message)
            {
                // Format the message with level and target info
                let formatted_message = if log_entry.fields.is_empty() {
                    format!(
                        "[{}] {}: {}",
                        log_entry.level, log_entry.target, log_entry.message
                    )
                } else {
                    let fields_str = log_entry
                        .fields
                        .iter()
                        .map(|(k, v)| format!("{}={}", k, v))
                        .collect::<Vec<_>>()
                        .join(" ");
                    format!(
                        "[{}] {}: {} {}",
                        log_entry.level, log_entry.target, log_entry.message, fields_str
                    )
                };

                Log {
                    message: formatted_message,
                    timestamp: chrono::Utc::now().to_rfc3339(),
                    level: log_entry.level,
                }
            } else {
                // Fallback for plain text messages
                Log {
                    message,
                    timestamp: chrono::Utc::now().to_rfc3339(),
                    level: "INFO".to_string(),
                }
            };

            match serde_json::to_string(&log) {
                Ok(s) => Ok::<_, std::io::Error>(s + "\n"),
                Err(e) => {
                    tracing::error!("Failed to serialize log: {}", e);
                    // Return empty string on error to keep stream alive
                    Ok::<_, std::io::Error>(String::new())
                }
            }
        });

        // Create a body from the stream for HTTP request
        let body = Body::wrap_stream(log_stream);

        // Send the streaming HTTP request with logs
        let result = http_client
            .post(log_url.as_ref())
            .header("Content-Type", "application/x-ndjson")
            .body(body)
            .send()
            .await;

        match result {
            Ok(_) => tracing::debug!("Log stream for job {} completed successfully", job_id),
            Err(e) => tracing::error!("Failed to send log stream for job {}: {}", job_id, e),
        }
    });

    log_sender
}

#[derive(Parser)]
#[command(
    color = clap::ColorChoice::Auto,
    dont_delimit_trailing_values = true,
)]
struct Cli {
    #[arg(short = 'u', long, default_value = "ws://cloud.devenv.sh/", value_parser = parse_uri)]
    host: Uri,

    #[arg(long, env = "RESOURCES_DIR")]
    resources_dir: PathBuf,

    #[arg(long, env = "DEVENV_STATE")]
    state_dir: PathBuf,
}

impl Cli {
    fn vm_config(&self) -> VmConfig {
        VmConfig {
            resources_dir: self.resources_dir.clone(),
            state_dir: self.state_dir.clone(),
        }
    }
}

fn parse_uri(s: &str) -> Result<Uri, String> {
    s.parse::<Uri>().map_err(|e| format!("Invalid URI: {}", e))
}

#[tokio::main]
async fn main() -> Result<()> {
    color_eyre::install()?;
    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer())
        .with(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    // Setup host networking for VMs on Linux
    #[cfg(target_os = "linux")]
    {
        use devenv_runner::vm_impl::linux_networking;
        linux_networking::setup_host_networking()
            .expect("Failed to setup host networking. This typically requires root privileges.");
    }

    let cli = Cli::parse();
    let vm_config = cli.vm_config();

    // Create resource manager with platform-specific defaults
    let resource_manager = Arc::new(ResourceManager::with_platform_defaults());

    // Log the detected resource limits
    tracing::info!(
        "System resources - CPUs: {}, Memory: {}MB{}",
        resource_manager.limits.max_cpus,
        resource_manager.limits.max_memory_bytes / (1024 * 1024),
        if let Some(max_instances) = resource_manager.limits.max_instances {
            format!(", Max instances: {max_instances}")
        } else {
            String::new()
        }
    );

    // Create VM completion channel
    let (completion_tx, mut completion_rx) = mpsc::channel::<VmCompletionEvent>(100);

    // Create job status channel
    let (job_status_tx, mut job_status_rx) = mpsc::channel::<JobStatusEvent>(100);

    // Create job manager
    let job_manager = Arc::new(JobManager::new(job_status_tx));

    // Create VM manager
    let vm_manager = Arc::new(VmManager::new(
        completion_tx,
        resource_manager.clone(),
        vm_config,
    ));

    // Create HTTP client for logging
    let http_client = HttpClient::new();

    // Create a shutdown channel
    let (shutdown_tx, mut shutdown_rx) = oneshot::channel::<()>();

    // Setup signal handlers for graceful shutdown
    tokio::spawn(handle_shutdown_signals(shutdown_tx));

    // Build WebSocket URI by appending path to host
    let base_uri = cli.host.to_string();
    let ws_uri_str = if base_uri.ends_with('/') {
        format!("{}api/v1/runner/ws", base_uri)
    } else {
        format!("{}/api/v1/runner/ws", base_uri)
    };
    let ws_uri = Arc::new(
        ws_uri_str
            .parse::<Uri>()
            .map_err(|e| eyre::eyre!("Failed to parse WebSocket URI: {}", e))?,
    );

    tracing::info!("Connecting to {}", ws_uri);

    // Connect to WebSocket server with retry logic
    let (mut client, mut read): (WebSocketClient, WsReadStream) = loop {
        tokio::select! {
            result = WebSocketClient::new((*ws_uri).clone(), None) => {
                match result {
                    Ok((client, read)) => break (client, Box::pin(read)),
                    Err(e) => {
                        tracing::error!("Failed to connect: {}", e);
                        tokio::time::sleep(Duration::from_secs(1)).await;
                    }
                }
            }
            Ok(_) = &mut shutdown_rx => {
                tracing::info!("Shutdown signal received during initial connection, exiting");
                return Ok(());
            }
        }
    };
    tracing::info!("Connected, waiting for jobs...");

    // Initial job request
    check_capacity_and_request_job(&mut client, &resource_manager).await?;

    let job_manager_clone = job_manager.clone();

    // Spawn task to handle VM completions
    tokio::spawn(async move {
        while let Some(event) = completion_rx.recv().await {
            // Resources are automatically released when the ResourceGuard in vm_task_impl drops

            // Convert VM exit status to job completion status
            let completion_status = match event.status {
                devenv_runner::vm::VmExitStatus::Success => CompletionStatus::Success,
                devenv_runner::vm::VmExitStatus::Failure => CompletionStatus::Failed,
            };

            // Attempt to update job status - state transition logic will handle conflicts
            // If job was already marked as canceled/timed out, this will be rejected
            if let Err(e) = job_manager_clone
                .complete_job(event.job_id, completion_status)
                .await
            {
                tracing::error!("Failed to update job status: {}", e);
            } else {
                tracing::info!(
                    "VM for job {} completed with status: {:?}",
                    event.job_id,
                    event.status
                );
            }
        }
    });

    // Clone for shutdown handler
    let vm_manager_clone = vm_manager.clone();
    let resource_manager_clone = resource_manager.clone();
    let job_manager_clone = job_manager.clone();
    let ws_url_clone = ws_uri.clone();

    // Main event loop with shutdown handling
    let mut shutdown_rx = shutdown_rx;
    let mut shutting_down = false;

    let main_loop_thread = tokio::spawn(async move {
        // Create metrics reporting interval
        let mut metrics_interval = tokio::time::interval(Duration::from_secs(1));
        metrics_interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

        'main: loop {
            // Exit if we're shutting down and all jobs are complete
            if shutting_down && job_manager.active_job_count().await == 0 {
                tracing::info!("All jobs have completed, closing WebSocket connection gracefully");
                // Close the WebSocket connection gracefully
                if let Err(e) = client.close().await {
                    tracing::warn!("Failed to close WebSocket connection gracefully: {}", e);
                }
                break 'main;
            }

            tokio::select! {
                // Check for shutdown signal
                Ok(_) = &mut shutdown_rx, if !shutting_down => {
                    let active_jobs = job_manager.active_job_count().await;
                    tracing::info!("Graceful shutdown initiated, waiting for {} active jobs to complete", active_jobs);
                    shutting_down = true;
                }

                // Handle job status events
                Some(event) = job_status_rx.recv() => {
                    match event.status {
                        JobStatus::Complete(status) => {
                            // Job completed, update backend
                            if let Err(e) = client
                                .send_message(
                                    ClientMessage::UpdateJobStatus {
                                        id: event.job_id,
                                        status: JobStatus::Complete(status.clone()),
                                    },
                                    None,
                                )
                                .await
                            {
                                tracing::error!("Failed to update job status: {}", e);
                            }

                            tracing::info!("Job {} completed with status: {:?}", event.job_id, status);

                            // Request another job if we have capacity and not shutting down
                            if !shutting_down {
                                if let Err(e) = check_capacity_and_request_job(&mut client, &resource_manager).await {
                                    tracing::error!("Failed to request new job: {}", e);
                                }
                            }
                        }
                        JobStatus::Running => {
                            tracing::info!("Job {} is now running", event.job_id);
                        }
                        JobStatus::Queued => {
                            tracing::info!("Job {} is queued", event.job_id);
                        }
                    }
                }

                // Process WebSocket messages
                ws_message = read.next(), if !shutting_down => {
                    match ws_message {
                        Some(Ok(message)) => handle_server_message(
                            message,
                            &mut client,
                            &vm_manager_clone,
                            &resource_manager_clone,
                            &job_manager_clone,
                            &http_client,
                            shutting_down,
                        ).await.unwrap(),
                        Some(Err(e)) => {
                            tracing::error!("WebSocket error: {}", e);
                            tokio::time::sleep(Duration::from_millis(500)).await;
                        }
                        None => {
                            if shutting_down && job_manager.active_job_count().await == 0 {
                                // If we're shutting down and all jobs are gone, exit
                                tracing::info!("WebSocket connection closed and all jobs are finished, exiting gracefully");
                                // Try to close the connection gracefully even though it may already be closed
                                let _ = client.close().await;
                                break 'main;
                            }

                            tracing::info!("WebSocket connection closed, attempting to reconnect...");

                            match reconnect_websocket((*ws_url_clone).clone()).await {
                                Ok((new_client, new_read)) => {
                                    client = new_client;
                                    read = new_read;
                                    tracing::info!("Successfully reconnected!");
                                    if !shutting_down {
                                        check_capacity_and_request_job(&mut client, &resource_manager).await.unwrap()
                                    }
                                }
                                Err(e) => {
                                    tracing::error!("Failed to reconnect: {}", e);
                                    // Try to close any remaining connection gracefully
                                    let _ = client.close().await;
                                    break 'main;
                                }
                            }
                        }
                    }
                }

                // Periodic metrics reporting
                _ = metrics_interval.tick() => {
                    let metrics = collect_metrics(&resource_manager, &job_manager).await;
                    if let Err(e) = client
                        .send_message(ClientMessage::ReportMetrics(metrics), None)
                        .await
                    {
                        tracing::error!("Failed to send metrics update: {}", e);
                    }
                }
            }
        }
    });

    #[cfg(target_os = "linux")]
    {
        // Wait for the main event loop to finish
        main_loop_thread.await?;

        tracing::info!("Runner gracefully exited");
        Ok(())
    }

    #[cfg(target_os = "macos")]
    {
        // On macOS, spawn the main tokio loop on a separate thread
        // so that dispatch_main() can run on the main thread
        let _tokio_handle = std::thread::spawn(move || {
            // Create a tokio runtime for the background thread
            let rt = tokio::runtime::Runtime::new().expect("Failed to create tokio runtime");
            rt.block_on(async { main_loop_thread.await.expect("Main loop failed") });

            tracing::info!("Runner gracefully exited");
            // Exit the process since dispatch_main() blocks forever
            std::process::exit(0);
        });

        tracing::debug!("Starting main dispatch queue on main thread");

        // Run dispatch_main() on the main thread - this blocks forever
        // The tokio thread will exit the process when complete
        dispatch2::dispatch_main()
    }
}

/// Collect current runner metrics
async fn collect_metrics(
    resource_manager: &ResourceManager,
    job_manager: &JobManager,
) -> RunnerMetrics {
    let (used_cpu_count, used_memory_mb) = resource_manager.get_usage_stats().await;
    let (active_jobs, queued_jobs, running_jobs) = job_manager.get_job_counts().await;

    let total_cpus = resource_manager.limits.max_cpus;
    let total_memory_mb = resource_manager.limits.max_memory_bytes / (1024 * 1024);

    // Calculate utilization percentages
    let cpu_utilization_percent = if total_cpus > 0 {
        (used_cpu_count as f32 / total_cpus as f32) * 100.0
    } else {
        0.0
    };

    let memory_utilization_percent = if total_memory_mb > 0 {
        (used_memory_mb as f32 / total_memory_mb as f32) * 100.0
    } else {
        0.0
    };

    RunnerMetrics {
        platform: devenv_runner::protocol::Platform::current(),
        cpu_count: total_cpus,
        memory_size_mb: total_memory_mb,
        used_cpu_count,
        used_memory_mb,
        cpu_utilization_percent,
        memory_utilization_percent,
        active_jobs,
        queued_jobs,
        running_jobs,
        max_instances: resource_manager.limits.max_instances,
    }
}

/// Handle server messages from WebSocket
async fn handle_server_message(
    message: ServerMessage,
    client: &mut WebSocketClient,
    vm_manager: &VmManager,
    resource_manager: &Arc<ResourceManager>,
    job_manager: &JobManager,
    http_client: &HttpClient,
    shutting_down: bool,
) -> Result<()> {
    match message {
        ServerMessage::NewJobAvailable { id, vm } => {
            // Skip new jobs if we're shutting down
            if shutting_down {
                tracing::info!("Ignoring new job {} while shutting down", id);
                return Ok(());
            }

            tracing::info!("New job available with ID: {}", id);

            // Check if we have enough resources
            if resource_manager
                .can_allocate(vm.cpu_count, vm.memory_size_mb)
                .await
            {
                tracing::debug!(
                    "Claiming job {} with {} CPUs and {}MB RAM",
                    id,
                    vm.cpu_count,
                    vm.memory_size_mb
                );

                client
                    .send_message(ClientMessage::ClaimJob { id, vm }, None)
                    .await?
            } else {
                tracing::debug!(
                    "Insufficient resources for job {} (needs {} CPUs, {}MB RAM) - Current: {}",
                    id,
                    vm.cpu_count,
                    vm.memory_size_mb,
                    resource_manager.resource_summary().await
                );
            }
        }
        ServerMessage::JobClaimed { id, vm, log_url } => {
            // If we're shutting down but somehow got a job claim response,
            // we should reject it
            if shutting_down {
                tracing::info!("Ignoring job claim {} while shutting down", id);
                return Ok(());
            }

            tracing::info!("Job {} claimed successfully", id);

            // Create job configuration
            let job_config = JobConfig {
                id,
                project_url: "https://github.com/cachix/devenv".to_string(),
                git_ref: None,
                tasks: vec!["build".to_string(), "test".to_string()],
                cachix_push: false,
                clone_depth: None,
            };

            // Register job with job manager
            job_manager.register_job(id, job_config.clone()).await?;

            // Set up log streaming
            let log_sender = setup_log_stream(
                http_client.clone(),
                log_url,
                id,
                vm.cpu_count,
                vm.memory_size_mb,
            )
            .await;

            // Launch VM for this job
            if let Err(e) = vm_manager
                .launch_vm(id, vm.clone(), job_config, log_sender.clone())
                .await
            {
                tracing::error!("Failed to launch VM: {}", e);

                // Resources will be automatically released when resource_guard is dropped

                // Send error via the log channel
                let error_msg = format!("Failed to launch VM: {e}");
                if let Err(e) = log_sender.send(error_msg.clone()).await {
                    tracing::error!("Failed to send error log: {}", e);
                }

                // Update job status to failed
                if let Err(e) = job_manager.complete_job(id, CompletionStatus::Failed).await {
                    tracing::error!("Failed to update job status: {}", e);
                }
            } else {
                // VM launched successfully
                if let Err(e) = job_manager.set_job_running(id).await {
                    tracing::error!("Failed to set job running: {}", e);
                }
            }
        }
        ServerMessage::JobTimedOut { id } => {
            tracing::info!("Job {} timed out, sending shutdown command", id);

            // Update job status to timed out
            if let Err(e) = job_manager
                .complete_job(id, CompletionStatus::TimedOut)
                .await
            {
                tracing::error!("Failed to update timed out job: {}", e);
            }

            // Send shutdown command to VM
            if let Err(e) = vm_manager.shutdown_vm(&id).await {
                tracing::error!("Failed to shutdown VM: {}", e);
                // Resources will be automatically released when the ResourceGuard in vm_task_impl drops
            }

            // The VM completion handler will handle backend status updates
            // when the VM actually exits
        }
        ServerMessage::JobCancelled { id } => {
            tracing::info!("Job {} cancelled by user, sending shutdown command", id);

            // Update job status to cancelled
            if let Err(e) = job_manager
                .complete_job(id, CompletionStatus::Cancelled)
                .await
            {
                tracing::error!("Failed to update cancelled job: {}", e);
            }

            // Send shutdown command to VM
            if let Err(e) = vm_manager.shutdown_vm(&id).await {
                tracing::error!("Failed to shutdown VM: {}", e);

                // If shutdown fails, make sure resources are released
                resource_manager.release_job(id).await;
            }

            // The VM completion handler will handle resource cleanup and backend status updates
            // when the VM actually exits
        }
    }

    Ok(())
}

/// Implement the function to handle shutdown signals
async fn handle_shutdown_signals(shutdown_tx: oneshot::Sender<()>) {
    // Handle SIGINT (Ctrl+C)
    let mut sigint = signal(SignalKind::interrupt()).expect("Failed to register SIGINT handler");
    // Handle SIGTERM
    let mut sigterm = signal(SignalKind::terminate()).expect("Failed to register SIGTERM handler");

    tokio::select! {
        _ = sigint.recv() => {
            tracing::info!("Received SIGINT, initiating graceful shutdown...");
        }
        _ = sigterm.recv() => {
            tracing::info!("Received SIGTERM, initiating graceful shutdown...");
        }
    }

    // Signal the main loop to begin shutdown process
    let _ = shutdown_tx.send(());
}
