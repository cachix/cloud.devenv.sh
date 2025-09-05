use crate::config::AppState;
use crate::github::model::{JobGitHub, SourceControlIntegration};
use axum::extract::State;
use axum::response::IntoResponse;
use axum_typed_websockets::{Message, TextJsonCodec, WebSocket, WebSocketUpgrade};
use devenv_runner::protocol::{ClientMessage, ServerMessage, VM};
use futures_util::stream::StreamExt;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{RwLock, mpsc};
use utoipa_axum::{router::OpenApiRouter, routes};

use super::model::Runner;
// Use job model types from the job module
use crate::job::model::{Job, JobStatus};

// Shared state for tracking runner connections
#[derive(Clone)]
pub struct RunnerState {
    // Map of runner_id to a channel for sending messages to that runner
    runners: Arc<RwLock<HashMap<uuid::Uuid, mpsc::Sender<ServerMessage>>>>,
}

impl RunnerState {
    pub fn new() -> Self {
        Self {
            runners: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    // Register a new runner
    pub async fn register(&self, runner_id: uuid::Uuid, tx: mpsc::Sender<ServerMessage>) {
        let mut runners = self.runners.write().await;
        runners.insert(runner_id, tx);
    }

    // Unregister a runner
    pub async fn unregister(&self, runner_id: &uuid::Uuid) {
        let mut runners = self.runners.write().await;
        runners.remove(runner_id);
    }

    // Try to send a message to a runner
    pub async fn try_send_to(&self, runner_id: &uuid::Uuid, msg: ServerMessage) -> bool {
        let mut success = false;
        let mut runners = self.runners.write().await;

        if let Some(tx) = runners.get_mut(runner_id) {
            success = tx.try_send(msg).is_ok();
        }

        success
    }

    /// Create a ServerMessage::NewJobAvailable from a Job
    fn create_job_notification(job: &crate::job::model::Job) -> ServerMessage {
        ServerMessage::NewJobAvailable {
            id: job.id,
            vm: VM {
                cpu_count: job.cpus as usize,
                memory_size_mb: job.memory_mb as u64,
                platform: job.platform.clone().into(),
            },
        }
    }

    /// Broadcast job availability to runners with matching platform
    pub async fn broadcast_job_available(
        &self,
        job: &crate::job::model::Job,
        pool: &diesel_async::pooled_connection::deadpool::Pool<diesel_async::AsyncPgConnection>,
    ) {
        // Create notification message with owned values
        let job_id = job.id; // Copy UUID
        let notification = Self::create_job_notification(job);

        // Get runner IDs and channels
        let runners_map = self.runners.read().await;
        if runners_map.is_empty() {
            tracing::debug!("No runners connected, skipping job broadcast");
            return;
        }

        // Get all runner IDs
        let runner_ids: Vec<uuid::Uuid> = runners_map.keys().cloned().collect();
        drop(runners_map); // Release the read lock early

        // Clone pool for owned access in task
        let pool_clone = pool.clone();

        // Get platform as string for database query
        let job_platform_str = job.platform.to_string();
        let platform_for_logging = job_platform_str.clone();

        // Spawn a task to find runners with matching platform and broadcast the job
        let notification_clone = notification.clone();
        let runner_state = self.clone();
        tokio::spawn(async move {
            if let Ok(conn) = pool_clone.get().await {
                // Find runners with matching platform
                let mut conn = conn;

                if let Ok(matching_runners) =
                    Runner::find_matching_platforms(&mut conn, &runner_ids, &job_platform_str).await
                {
                    let mut broadcast_count = 0;

                    // Lock the runner map again
                    let runners = runner_state.runners.read().await;

                    // Send notification only to matching runners
                    for runner_id in matching_runners {
                        if let Some(tx) = runners.get(&runner_id) {
                            if tx.try_send(notification_clone.clone()).is_ok() {
                                broadcast_count += 1;
                            }
                        }
                    }

                    if broadcast_count > 0 {
                        tracing::info!(
                            "Broadcast job {} availability to {} platform-compatible runners",
                            job_id,
                            broadcast_count
                        );
                    } else {
                        tracing::warn!(
                            "No compatible runners available for job {} (platform: {})",
                            job_id,
                            platform_for_logging
                        );
                    }
                } else {
                    tracing::error!("Failed to query runner platforms from database");
                }
            } else {
                tracing::error!(
                    "Failed to get database connection for platform-aware job broadcasting"
                );
            }
        });
    }
}

#[utoipa::path(get, path = "/ws", responses((status = OK, body = ())))]
#[tracing::instrument(skip_all)]
async fn handler(
    ws: WebSocketUpgrade<ServerMessage, ClientMessage, TextJsonCodec>,
    headers: axum::http::HeaderMap,
    State(app_state): State<AppState>,
) -> axum::response::Response {
    // Access the runner state through the AppState
    let runner_state = app_state.runner_state.clone();

    // Extract platform from the header (default to x86_64-linux if not provided)
    let platform_str = headers
        .get("X-Runner-Platform")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("x86_64-linux");

    // Parse the platform string to our Platform type
    let platform = platform_str
        .parse()
        .unwrap_or(crate::job::model::Platform::X86_64Linux);

    // Create a new runner with the platform information
    let runner_result = Runner::new(&app_state.pool, platform).await;

    if let Err(e) = runner_result {
        tracing::error!("Failed to create runner: {}", e);
        return axum::http::StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    let runner = runner_result.unwrap();
    let runner_id = runner.id;
    tracing::debug!(
        "Created runner {} with platform {}",
        runner_id,
        platform_str
    );

    // Return the WebSocketUpgrade
    ws.on_upgrade(move |socket| spawn_runner(socket, app_state, runner_id, runner_state))
        .into_response()
}

async fn spawn_runner(
    mut socket: WebSocket<ServerMessage, ClientMessage, TextJsonCodec>,
    app_state: AppState,
    runner_id: uuid::Uuid,
    runner_state: RunnerState,
) {
    // Create a channel for sending messages to this specific runner
    let (tx, mut rx) = mpsc::channel::<ServerMessage>(32);

    // Register the runner in the shared state
    runner_state.register(runner_id, tx).await;

    // Send initial job check on connection
    check_and_send_job(&mut socket, &app_state, &runner_id).await;

    loop {
        tokio::select! {
            // Handle incoming messages from the client
            client_msg = socket.next() => {
                match client_msg {
                    Some(Ok(Message::Item(client_msg))) => {
                        match client_msg {
                            ClientMessage::ClaimJob { id, vm } => {
                                let conn = &mut app_state.pool.get().await.unwrap();
                                tracing::info!("Runner {} claiming job {}", runner_id, id);
                                let rows = Job::claim_job_for_runner(conn, id, runner_id)
                                    .await
                                    .unwrap_or(0);
                                if rows == 1 {
                                    <JobGitHub as SourceControlIntegration>::update_status(
                                        app_state.clone(),
                                        devenv_runner::protocol::JobStatus::Running,
                                        id,
                                    )
                                    .await
                                    .ok();
                                    // Get the logger URL for this job
                                    let logger_url = format!("{}/{}", app_state.config.logger_url, id);

                                    socket
                                        .send(Message::Item(ServerMessage::JobClaimed {
                                            id,
                                            vm,
                                            log_url: std::str::FromStr::from_str(&logger_url).unwrap(),
                                        }))
                                        .await
                                        .ok();
                                }
                            }
                            ClientMessage::UpdateJobStatus { id, status } => {
                                // TODO: authorize job_id against runner
                                let conn = &mut app_state.pool.get().await.unwrap();
                                Job::update_job_status(conn, id, &JobStatus(status.clone()))
                                    .await
                                    .ok();

                                <JobGitHub as SourceControlIntegration>::update_status(
                                    app_state.clone(),
                                    status,
                                    id,
                                )
                                .await
                                .ok();

                                // Check for new jobs only after a job status update (VM finished)
                                check_and_send_job(&mut socket, &app_state, &runner_id).await;
                            }
                            ClientMessage::RequestJob => {
                                // Runner has capacity and is requesting a job
                                check_and_send_job(&mut socket, &app_state, &runner_id).await;
                            }
                            ClientMessage::ReportMetrics(metrics) => {
                                // Log runner metrics as a tracing event
                                tracing::trace!(
                                    runner_id = %runner_id,
                                    platform = %metrics.platform,
                                    cpu_count = metrics.cpu_count,
                                    memory_size_mb = metrics.memory_size_mb,
                                    used_cpu_count = metrics.used_cpu_count,
                                    used_memory_mb = metrics.used_memory_mb,
                                    cpu_utilization_percent = metrics.cpu_utilization_percent,
                                    memory_utilization_percent = metrics.memory_utilization_percent,
                                    active_jobs = metrics.active_jobs,
                                    queued_jobs = metrics.queued_jobs,
                                    running_jobs = metrics.running_jobs,
                                    max_instances = ?metrics.max_instances,
                                    "Runner metrics report"
                                );
                            }
                        }
                    }
                    Some(Ok(_)) | None => {
                        break;
                    }
                    Some(Err(err)) => {
                        tracing::error!("{}", err);
                        break;
                    }
                }
            }

            // Handle timeout messages from the timeout checker task
            server_msg = rx.recv() => {
                if let Some(msg) = server_msg {
                    if let Err(e) = socket.send(Message::Item(msg)).await {
                        tracing::error!("Failed to send timeout message to runner: {}", e);
                        break;
                    }
                } else {
                    // Channel closed, runner should exit
                    break;
                }
            }
        }
    }

    // Unregister the runner when the connection closes
    runner_state.unregister(&runner_id).await;
}

/// Check for available jobs and send it to a runner if compatible with the runner's platform
/// Return true if a job was found and sent
async fn check_and_send_job(
    socket: &mut WebSocket<ServerMessage, ClientMessage, TextJsonCodec>,
    app_state: &AppState,
    runner_id: &uuid::Uuid,
) -> bool {
    // Get the runner's platform
    let conn = &mut app_state.pool.get().await.unwrap();
    let runner_platform_result = Runner::get_platform(conn, runner_id).await;

    if let Err(e) = runner_platform_result {
        tracing::error!("Failed to get runner platform: {}", e);
        return false;
    }

    let runner_platform_str = runner_platform_result.unwrap();
    // Parse the platform string to our Platform type
    let runner_platform = runner_platform_str
        .parse()
        .unwrap_or(crate::job::model::Platform::X86_64Linux);

    // Look for jobs matching the runner's platform
    let job_result = Job::find_queued_job_for_platform(conn, &runner_platform).await;

    if let Ok(Some(job)) = job_result {
        // Create and send job notification
        let notification = RunnerState::create_job_notification(&job);
        let send_result = socket.send(Message::Item(notification)).await;

        if send_result.is_ok() {
            tracing::info!(
                "Sent job {} to runner {} (platform: {})",
                job.id,
                runner_id,
                runner_platform_str
            );
            return true;
        }
    }

    false
}

// Task that periodically checks for timed out jobs
async fn job_timeout_checker(app_state: AppState, runner_state: RunnerState) {
    let interval = tokio::time::Duration::from_secs(30); // Check every 30 seconds
    let mut interval_timer = tokio::time::interval(interval);

    loop {
        interval_timer.tick().await;

        let timeout_seconds = app_state.config.job.timeout_seconds;

        // Find jobs that have exceeded their timeout
        let conn = &mut app_state.pool.get().await.unwrap();
        let expired_jobs_result = Job::find_expired_jobs(conn, timeout_seconds).await;

        if let Ok(expired_jobs) = expired_jobs_result {
            for job in expired_jobs {
                if let Some(runner_id) = job.runner_id {
                    // Try to send timeout notification to the runner if connected
                    let runner_notified = runner_state
                        .try_send_to(&runner_id, ServerMessage::JobTimedOut { id: job.id })
                        .await;

                    if !runner_notified {
                        tracing::warn!(
                            "Runner {} not available for job {}, updating status directly",
                            runner_id,
                            job.id
                        );

                        // If we can't reach the runner, update the job status directly
                        let mut job_clone = job.clone();
                        if let Err(e) = job_clone
                            .complete(
                                &mut app_state.pool.get().await.unwrap(),
                                devenv_runner::protocol::CompletionStatus::TimedOut,
                            )
                            .await
                        {
                            tracing::error!("Failed to update job status to timed_out: {}", e);
                        } else {
                            // Update GitHub status
                            <JobGitHub as SourceControlIntegration>::update_status(
                                app_state.clone(),
                                devenv_runner::protocol::JobStatus::Complete(
                                    devenv_runner::protocol::CompletionStatus::TimedOut,
                                ),
                                job.id,
                            )
                            .await
                            .ok();
                        }
                    }
                }
            }
        }
    }
}

pub fn router() -> OpenApiRouter<AppState> {
    // We'll use the RunnerState from AppState instead of creating it here
    OpenApiRouter::new().routes(routes!(handler))
}

// Start the job timeout checker task with the AppState
pub fn start_job_timeout_checker(app_state: AppState) {
    let runner_state = app_state.runner_state.clone();

    // Spawn a task to check for timed out jobs
    tokio::spawn(async move {
        job_timeout_checker(app_state, runner_state).await;
    });
}

// Public function to notify compatible runners about a new job
pub async fn notify_runners_about_job(app_state: &AppState, job: &crate::job::model::Job) {
    app_state
        .runner_state
        .broadcast_job_available(job, &app_state.pool)
        .await;
}
