//! GitHub API integration layer.
//!
//! This module handles all external GitHub API calls, keeping them separate
//! from database operations in model.rs.

use crate::config::AppState;
use devenv_runner::protocol;
use eyre::Result;

/// Parameters for creating a GitHub check run.
pub struct CreateCheckRunParams<'a> {
    pub owner_login: &'a str,
    pub repo_name: &'a str,
    pub job_id: uuid::Uuid,
    pub job_platform: &'a str,
    pub rev: &'a str,
    pub base_url: &'a str,
}

/// Parameters for updating a GitHub check run status.
pub struct UpdateCheckRunParams<'a> {
    pub owner_login: &'a str,
    pub repo_name: &'a str,
    pub check_run_id: i64,
}

/// GitHub API client wrapper for installation-authenticated operations.
pub struct GitHubApiClient {
    client: octocrab::Octocrab,
}

impl GitHubApiClient {
    /// Creates a new GitHub API client for a specific installation.
    pub fn for_installation(app_state: &AppState, installation_id: i64) -> Result<Self> {
        let client = app_state
            .github
            .installation(octocrab::models::InstallationId(installation_id as u64))?;
        Ok(Self { client })
    }

    /// Returns the underlying octocrab client for operations not covered by this wrapper.
    #[must_use]
    pub fn into_inner(self) -> octocrab::Octocrab {
        self.client
    }

    /// Creates a GitHub check run and returns the check run ID.
    pub async fn create_check_run(&self, params: CreateCheckRunParams<'_>) -> Result<i64> {
        let checks = self.client.checks(params.owner_login, params.repo_name);
        let details_url = format!(
            "{}/github/{}/{}#{}",
            params.base_url, params.owner_login, params.repo_name, params.job_id
        );

        let check_run = checks
            .create_check_run(format!("devenv ({})", params.job_platform), params.rev)
            .details_url(details_url)
            .external_id(params.job_id)
            .status(octocrab::params::checks::CheckRunStatus::Queued)
            .send()
            .await?;

        Ok(check_run.id.0 as i64)
    }

    /// Updates a check run to "in progress" status.
    ///
    /// Returns the timestamp used for the started_at field.
    pub async fn set_check_run_in_progress(
        &self,
        params: UpdateCheckRunParams<'_>,
    ) -> Result<chrono::DateTime<chrono::Utc>> {
        let checks = self.client.checks(params.owner_login, params.repo_name);
        let check =
            checks.update_check_run(octocrab::models::CheckRunId(params.check_run_id as u64));

        let now = chrono::Utc::now();
        check
            .status(octocrab::params::checks::CheckRunStatus::InProgress)
            .started_at(now)
            .send()
            .await?;

        Ok(now)
    }

    /// Updates a check run to "completed" status with the given conclusion.
    ///
    /// Returns the timestamp used for the completed_at field.
    pub async fn set_check_run_completed(
        &self,
        params: UpdateCheckRunParams<'_>,
        completion_status: &protocol::CompletionStatus,
    ) -> Result<chrono::DateTime<chrono::Utc>> {
        let checks = self.client.checks(params.owner_login, params.repo_name);
        let check =
            checks.update_check_run(octocrab::models::CheckRunId(params.check_run_id as u64));

        let now = chrono::Utc::now();
        let conclusion = match completion_status {
            protocol::CompletionStatus::Cancelled => {
                octocrab::params::checks::CheckRunConclusion::Cancelled
            }
            protocol::CompletionStatus::Failed => {
                octocrab::params::checks::CheckRunConclusion::Failure
            }
            protocol::CompletionStatus::Success => {
                octocrab::params::checks::CheckRunConclusion::Success
            }
            protocol::CompletionStatus::TimedOut => {
                octocrab::params::checks::CheckRunConclusion::TimedOut
            }
            protocol::CompletionStatus::Skipped => {
                octocrab::params::checks::CheckRunConclusion::Skipped
            }
        };

        check
            .status(octocrab::params::checks::CheckRunStatus::Completed)
            .completed_at(now)
            .conclusion(conclusion)
            .send()
            .await?;

        Ok(now)
    }

    /// Checks if a file exists in a repository at a specific git ref.
    pub async fn file_exists(
        &self,
        owner: &str,
        repo: &str,
        path: &str,
        git_ref: &str,
    ) -> Result<bool> {
        let content = self
            .client
            .repos(owner, repo)
            .get_content()
            .path(path)
            .r#ref(git_ref)
            .send()
            .await?;

        Ok(!content.items.is_empty())
    }

    /// Gets the decoded content of a file in a repository at a specific git ref.
    ///
    /// Returns `None` if the file doesn't exist or content cannot be decoded.
    pub async fn get_file_content(
        &self,
        owner: &str,
        repo: &str,
        path: &str,
        git_ref: &str,
    ) -> Option<String> {
        let content = self
            .client
            .repos(owner, repo)
            .get_content()
            .path(path)
            .r#ref(git_ref)
            .send()
            .await
            .ok()?;

        if content.items.is_empty() {
            return None;
        }

        content.items[0].decoded_content()
    }
}
