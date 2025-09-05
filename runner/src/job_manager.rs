use crate::protocol::{CompletionStatus, JobConfig, JobStatus};
use eyre::Result;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{RwLock, mpsc};
use uuid::Uuid;

/// Event emitted when a job's status changes
#[derive(Debug, Clone)]
pub struct JobStatusEvent {
    pub job_id: Uuid,
    pub status: JobStatus,
}

/// Job tracking information
#[derive(Debug, Clone)]
pub struct JobInfo {
    pub id: Uuid,
    pub config: JobConfig,
    pub status: JobStatus,
}

impl JobInfo {
    /// Create a new JobInfo with initial status
    pub fn new(id: Uuid, config: JobConfig) -> Self {
        Self {
            id,
            config,
            status: JobStatus::Queued,
        }
    }
}

/// Manages job lifecycle and status updates
pub struct JobManager {
    // All jobs tracked by the manager
    jobs: Arc<RwLock<HashMap<Uuid, JobInfo>>>,
    // Channel for emitting job status events
    status_tx: mpsc::Sender<JobStatusEvent>,
}

impl JobManager {
    /// Create a new JobManager
    pub fn new(status_tx: mpsc::Sender<JobStatusEvent>) -> Self {
        Self {
            jobs: Arc::new(RwLock::new(HashMap::new())),
            status_tx,
        }
    }

    /// Register a new job
    pub async fn register_job(&self, id: Uuid, config: JobConfig) -> Result<()> {
        let job_info = JobInfo::new(id, config);

        let mut jobs = self.jobs.write().await;
        jobs.insert(id, job_info);

        // Emit event for new job
        let event = JobStatusEvent {
            job_id: id,
            status: JobStatus::Queued,
        };

        if let Err(e) = self.status_tx.send(event).await {
            tracing::error!("Failed to send job registered event: {}", e);
        }

        Ok(())
    }

    /// Update a job's status following explicitly allowed state transitions
    pub async fn update_job_status(&self, job_id: Uuid, status: JobStatus) -> Result<()> {
        let mut jobs = self.jobs.write().await;

        let job = jobs
            .get_mut(&job_id)
            .ok_or_else(|| eyre::eyre!("Job not found: {}", job_id))?;

        // Don't update if status hasn't changed
        if job.status == status {
            return Ok(());
        }

        // Check if transition is allowed based on current and target state
        let transition_allowed = match (&job.status, &status) {
            (JobStatus::Queued, JobStatus::Running) => true,
            (JobStatus::Queued, JobStatus::Complete(CompletionStatus::Cancelled)) => true,
            (JobStatus::Running, JobStatus::Complete(_)) => true,
            // All other transitions are not allowed
            _ => false,
        };

        if !transition_allowed {
            tracing::debug!(
                "Invalid job status transition rejected: {} from {:?} to {:?}",
                job_id,
                job.status,
                status
            );
            return Ok(());
        }

        // Update job status
        job.status = status.clone();

        // Emit status change event
        let event = JobStatusEvent { job_id, status };

        if let Err(e) = self.status_tx.send(event).await {
            tracing::error!("Failed to send job status event: {}", e);
        }

        Ok(())
    }

    /// Get information about a job
    pub async fn get_job(&self, job_id: &Uuid) -> Option<JobInfo> {
        let jobs = self.jobs.read().await;
        jobs.get(job_id).cloned()
    }

    /// Update a job to running state
    pub async fn set_job_running(&self, job_id: Uuid) -> Result<()> {
        self.update_job_status(job_id, JobStatus::Running).await
    }

    /// Mark a job as complete
    pub async fn complete_job(&self, job_id: Uuid, status: CompletionStatus) -> Result<()> {
        self.update_job_status(job_id, JobStatus::Complete(status))
            .await
    }

    /// Check if a job exists
    pub async fn job_exists(&self, job_id: &Uuid) -> bool {
        let jobs = self.jobs.read().await;
        jobs.contains_key(job_id)
    }

    /// Get the total number of jobs
    pub async fn job_count(&self) -> usize {
        let jobs = self.jobs.read().await;
        jobs.len()
    }

    /// Get number of jobs with active status (not completed)
    pub async fn active_job_count(&self) -> usize {
        let jobs = self.jobs.read().await;
        jobs.values()
            .filter(|job| !matches!(job.status, JobStatus::Complete(_)))
            .count()
    }

    /// Get job counts by status
    pub async fn get_job_counts(&self) -> (usize, usize, usize) {
        let jobs = self.jobs.read().await;
        let mut queued = 0;
        let mut running = 0;
        let mut active = 0;

        for job in jobs.values() {
            match &job.status {
                JobStatus::Queued => {
                    queued += 1;
                    active += 1;
                }
                JobStatus::Running => {
                    running += 1;
                    active += 1;
                }
                JobStatus::Complete(_) => {}
            }
        }

        (active, queued, running)
    }
}
