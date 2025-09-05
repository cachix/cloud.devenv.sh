use crate::auth::BetaUser;
use crate::config::AppState;
use crate::error::Result;
use crate::github::model::SourceControlIntegration;
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use utoipa_axum::{router::OpenApiRouter, routes};

use super::model;

use devenv_runner::protocol::CompletionStatus;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct JobResponse {
    pub job: model::Job,
    pub github: crate::github::model::JobGitHub,
    pub commit: crate::github::model::GitHubCommit,
    #[schema(format = "uri")]
    pub log_url: String,
}

/// Get details for a specific job
///
/// Returns job information along with GitHub data
#[utoipa::path(
    get,
    path = "/{id}",
    responses(
        (status = 200, description = "Job found", body = JobResponse),
        (status = 404, description = "Job not found")
    ),
    params(
        ("id" = uuid::Uuid, Path, description = "The unique identifier of the job"),
    )
)]
async fn get_job(
    _user: BetaUser,
    State(app_state): State<AppState>,
    Path(id): Path<uuid::Uuid>,
) -> Result<Json<JobResponse>> {
    let conn = &mut app_state.pool.get().await?;

    // Get the job with all its GitHub details in one operation
    let (job, github, commit) = model::Job::get_with_github_details(conn, id).await?;

    // Generate a log URL for this job - using the logger service
    let log_url = job.log_url(&app_state.config.logger_url);

    Ok(Json(JobResponse {
        job,
        github,
        commit,
        log_url,
    }))
}

/// Cancel a job
///
/// Cancels a job that is currently in progress or queued
#[utoipa::path(
    post,
    path = "/{id}/cancel",
    responses(
        (status = 200, description = "Job cancelled successfully"),
        (status = 404, description = "Job not found"),
        (status = 400, description = "Job cannot be cancelled (neither queued nor in progress)")
    ),
    params(
        ("id" = uuid::Uuid, Path, description = "The unique identifier of the job"),
    )
)]
#[tracing::instrument(skip_all)]
async fn cancel_job(
    _user: BetaUser,
    State(app_state): State<AppState>,
    Path(id): Path<uuid::Uuid>,
) -> impl IntoResponse {
    let conn = &mut app_state.pool.get().await.unwrap();

    // Use the model's cancel method which handles locking and race conditions
    match model::Job::cancel(conn, id).await {
        Ok((true, Some(job))) => {
            // Determine the original status for GitHub update
            let completion_status = match job.status.0 {
                devenv_runner::protocol::JobStatus::Complete(
                    devenv_runner::protocol::CompletionStatus::Skipped,
                ) => CompletionStatus::Skipped,
                _ => CompletionStatus::Cancelled,
            };

            // Check if job was running and needs runner notification
            let was_running = completion_status == CompletionStatus::Cancelled;

            if was_running {
                if let Some(runner_id) = job.runner_id {
                    // Try to send cancellation to runner if it's connected
                    app_state
                        .runner_state
                        .try_send_to(
                            &runner_id,
                            devenv_runner::protocol::ServerMessage::JobCancelled { id },
                        )
                        .await;
                }
            }

            // Update GitHub status
            <crate::github::model::JobGitHub as SourceControlIntegration>::update_status(
                app_state,
                devenv_runner::protocol::JobStatus::Complete(completion_status),
                id,
            )
            .await
            .ok();

            StatusCode::OK
        }
        Ok((true, None)) => {
            // This shouldn't happen with our current implementation
            StatusCode::INTERNAL_SERVER_ERROR
        }
        Ok((false, _)) => {
            // Job is not in a cancellable state
            StatusCode::BAD_REQUEST
        }
        Err(diesel::result::Error::NotFound) => StatusCode::NOT_FOUND,
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR,
    }
}

/// Retry a failed job
///
/// Creates a new job with the same configuration as the failed job
#[utoipa::path(
    post,
    path = "/{id}/retry-job",
    responses(
        (status = 200, description = "Job retry initiated successfully", body = JobResponse),
        (status = 404, description = "Job not found"),
        (status = 400, description = "Job cannot be retried (not failed)")
    ),
    params(
        ("id" = uuid::Uuid, Path, description = "The unique identifier of the job"),
    )
)]
#[tracing::instrument(skip_all)]
async fn retry_job(
    _user: BetaUser,
    State(app_state): State<AppState>,
    Path(id): Path<uuid::Uuid>,
) -> Result<Json<JobResponse>> {
    let conn = &mut app_state.pool.get().await?;

    // Get the original job with GitHub details
    let (job, _github, commit) = model::Job::get_with_github_details(conn, id)
        .await
        .map_err(|_| color_eyre::eyre::eyre!("Job not found or missing GitHub data"))?;

    // Check if the job can be retried
    if !job.is_retryable() {
        return Err(color_eyre::eyre::eyre!(
            "Job {} cannot be retried (status: {:?})",
            id,
            job.status
        )
        .into());
    }

    // Create the retry job in a transaction
    let retried_job = conn
        .build_transaction()
        .run::<_, diesel::result::Error, _>(|conn| Box::pin(async move { job.retry(conn).await }))
        .await
        .map_err(|e| color_eyre::eyre::eyre!("Failed to create retry job: {}", e))?;

    // Create the GitHub check run and JobGitHub record
    let job_github = crate::github::model::JobGitHub::create_with_check_run(
        conn,
        &app_state,
        &retried_job,
        &commit,
    )
    .await
    .map_err(|e| color_eyre::eyre::eyre!("Job created but GitHub check run failed: {}", e))?;

    // Generate log URL and notify runners
    let log_url = retried_job.log_url(&app_state.config.logger_url);
    crate::runner::serve::notify_runners_about_job(&app_state, &retried_job).await;

    Ok(Json(JobResponse {
        job: retried_job,
        github: job_github,
        commit,
        log_url,
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(get_job))
        .routes(routes!(cancel_job))
        .routes(routes!(retry_job))
}
