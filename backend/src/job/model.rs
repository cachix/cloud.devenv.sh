use crate::schema::jobs;
use diesel::deserialize::{FromSql, FromSqlRow};
use diesel::expression::AsExpression;
use diesel::prelude::*;
use diesel::serialize::ToSql;
use diesel_async::AsyncPgConnection;
use diesel_async::RunQueryDsl;
use eyre::Result;
use serde::{Deserialize, Serialize};
use std::io::Write;
use strum_macros::{Display, EnumString};
use utoipa::ToSchema;
use uuid::Uuid;

#[derive(
    Debug, Serialize, Deserialize, AsExpression, FromSqlRow, Display, EnumString, ToSchema, Clone,
)]
#[diesel(sql_type = diesel::sql_types::Text)]
#[strum()]
pub enum Platform {
    #[strum(serialize = "x86_64-linux")]
    X86_64Linux,
    #[strum(serialize = "aarch64-darwin")]
    AArch64Darwin,
}

impl ToSql<diesel::sql_types::Text, diesel::pg::Pg> for Platform {
    fn to_sql(
        &self,
        out: &mut diesel::serialize::Output<diesel::pg::Pg>,
    ) -> diesel::serialize::Result {
        out.write_all(self.to_string().as_bytes())?;
        Ok(diesel::serialize::IsNull::No)
    }
}

impl FromSql<diesel::sql_types::Text, diesel::pg::Pg> for Platform {
    fn from_sql(bytes: diesel::pg::PgValue<'_>) -> diesel::deserialize::Result<Self> {
        let string = <String as FromSql<diesel::sql_types::Text, diesel::pg::Pg>>::from_sql(bytes)?;
        string.parse().map_err(|_| "Unrecognized platform".into())
    }
}

// Implement From trait for converting between platform types
impl From<Platform> for devenv_runner::protocol::Platform {
    fn from(platform: Platform) -> Self {
        match platform {
            Platform::X86_64Linux => devenv_runner::protocol::Platform::X86_64Linux,
            Platform::AArch64Darwin => devenv_runner::protocol::Platform::AArch64Darwin,
        }
    }
}

impl From<devenv_runner::protocol::Platform> for Platform {
    fn from(platform: devenv_runner::protocol::Platform) -> Self {
        match platform {
            devenv_runner::protocol::Platform::X86_64Linux => Platform::X86_64Linux,
            devenv_runner::protocol::Platform::AArch64Darwin => Platform::AArch64Darwin,
        }
    }
}

#[derive(Debug, Serialize, Deserialize, AsExpression, FromSqlRow, Clone, ToSchema)]
#[diesel(sql_type = diesel::sql_types::Text)]
pub struct JobStatus(pub devenv_runner::protocol::JobStatus);

impl JobStatus {
    pub fn new(status: devenv_runner::protocol::JobStatus) -> Self {
        Self(status)
    }

    pub fn queued() -> Self {
        Self(devenv_runner::protocol::JobStatus::Queued)
    }

    pub fn running() -> Self {
        Self(devenv_runner::protocol::JobStatus::Running)
    }

    pub fn complete(completion: devenv_runner::protocol::CompletionStatus) -> Self {
        Self(devenv_runner::protocol::JobStatus::Complete(completion))
    }

    pub fn failed() -> Self {
        Self::complete(devenv_runner::protocol::CompletionStatus::Failed)
    }

    pub fn success() -> Self {
        Self::complete(devenv_runner::protocol::CompletionStatus::Success)
    }

    pub fn cancelled() -> Self {
        Self::complete(devenv_runner::protocol::CompletionStatus::Cancelled)
    }

    pub fn timed_out() -> Self {
        Self::complete(devenv_runner::protocol::CompletionStatus::TimedOut)
    }

    pub fn skipped() -> Self {
        Self::complete(devenv_runner::protocol::CompletionStatus::Skipped)
    }
}

impl ToSql<diesel::sql_types::Text, diesel::pg::Pg> for JobStatus {
    fn to_sql(
        &self,
        out: &mut diesel::serialize::Output<diesel::pg::Pg>,
    ) -> diesel::serialize::Result {
        match self.0 {
            devenv_runner::protocol::JobStatus::Queued => out.write_all(b"queued")?,
            devenv_runner::protocol::JobStatus::Running => out.write_all(b"running")?,
            devenv_runner::protocol::JobStatus::Complete(
                devenv_runner::protocol::CompletionStatus::Failed,
            ) => out.write_all(b"failed")?,
            devenv_runner::protocol::JobStatus::Complete(
                devenv_runner::protocol::CompletionStatus::Success,
            ) => out.write_all(b"success")?,
            devenv_runner::protocol::JobStatus::Complete(
                devenv_runner::protocol::CompletionStatus::Cancelled,
            ) => out.write_all(b"cancelled")?,
            devenv_runner::protocol::JobStatus::Complete(
                devenv_runner::protocol::CompletionStatus::TimedOut,
            ) => out.write_all(b"timed_out")?,
            devenv_runner::protocol::JobStatus::Complete(
                devenv_runner::protocol::CompletionStatus::Skipped,
            ) => out.write_all(b"skipped")?,
        }
        Ok(diesel::serialize::IsNull::No)
    }
}

impl FromSql<diesel::sql_types::Text, diesel::pg::Pg> for JobStatus {
    fn from_sql(bytes: diesel::pg::PgValue<'_>) -> diesel::deserialize::Result<Self> {
        let string = <String as FromSql<diesel::sql_types::Text, diesel::pg::Pg>>::from_sql(bytes)?;
        match string.as_str() {
            "queued" => Ok(JobStatus(devenv_runner::protocol::JobStatus::Queued)),
            "running" => Ok(JobStatus(devenv_runner::protocol::JobStatus::Running)),
            "failed" => Ok(JobStatus(devenv_runner::protocol::JobStatus::Complete(
                devenv_runner::protocol::CompletionStatus::Failed,
            ))),
            "success" => Ok(JobStatus(devenv_runner::protocol::JobStatus::Complete(
                devenv_runner::protocol::CompletionStatus::Success,
            ))),
            "cancelled" => Ok(JobStatus(devenv_runner::protocol::JobStatus::Complete(
                devenv_runner::protocol::CompletionStatus::Cancelled,
            ))),
            "timed_out" => Ok(JobStatus(devenv_runner::protocol::JobStatus::Complete(
                devenv_runner::protocol::CompletionStatus::TimedOut,
            ))),
            "skipped" => Ok(JobStatus(devenv_runner::protocol::JobStatus::Complete(
                devenv_runner::protocol::CompletionStatus::Skipped,
            ))),
            _ => Err("Unrecognized status".into()),
        }
    }
}
#[derive(Debug, Queryable, Selectable, Deserialize, Serialize, ToSchema, Identifiable, Clone)]
#[diesel(table_name = jobs)]
pub struct Job {
    pub id: uuid::Uuid,
    pub platform: Platform,
    pub status: JobStatus,
    pub started_at: Option<chrono::DateTime<chrono::Utc>>,
    pub finished_at: Option<chrono::DateTime<chrono::Utc>>,
    pub runner_id: Option<uuid::Uuid>,
    pub cpus: i32,
    pub memory_mb: i64,
    pub retried_job_id: Option<uuid::Uuid>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub previous_job_id: Option<uuid::Uuid>,
}

impl Job {
    pub async fn new(
        conn: &mut AsyncPgConnection,
        platform: Platform,
        cpus: Option<i32>,
        memory_mb: Option<i64>,
    ) -> Result<Self, diesel::result::Error> {
        let job = diesel::insert_into(jobs::table)
            .values((
                jobs::id.eq(Uuid::now_v7()),
                jobs::platform.eq(platform),
                jobs::status.eq(JobStatus::queued()),
                jobs::cpus.eq(cpus.unwrap_or(2)),
                jobs::memory_mb.eq(memory_mb.unwrap_or(256)),
            ))
            .get_result(conn)
            .await?;
        Ok(job)
    }

    pub async fn get_by_id(
        conn: &mut AsyncPgConnection,
        id: Uuid,
    ) -> Result<Self, diesel::result::Error> {
        use crate::schema::jobs;

        // Simply get the job by id
        jobs::table
            .filter(jobs::id.eq(id))
            .first::<Self>(conn)
            .await
    }

    pub async fn update_status(
        &mut self,
        conn: &mut AsyncPgConnection,
        status: JobStatus,
    ) -> Result<(), diesel::result::Error> {
        diesel::update(jobs::table)
            .filter(jobs::id.eq(self.id))
            .set(jobs::status.eq(status.clone()))
            .execute(conn)
            .await?;
        self.status = status;
        Ok(())
    }

    pub async fn assign_to_runner(
        &mut self,
        conn: &mut AsyncPgConnection,
        runner_id: Uuid,
    ) -> Result<(), diesel::result::Error> {
        let now = chrono::Utc::now();
        diesel::update(jobs::table)
            .filter(jobs::id.eq(self.id))
            .set((
                jobs::runner_id.eq(runner_id),
                jobs::started_at.eq(now),
                jobs::status.eq(JobStatus::running()),
            ))
            .execute(conn)
            .await?;
        self.runner_id = Some(runner_id);
        self.started_at = Some(now);
        self.status = JobStatus::running();
        Ok(())
    }

    pub async fn complete(
        &mut self,
        conn: &mut AsyncPgConnection,
        completion_status: devenv_runner::protocol::CompletionStatus,
    ) -> Result<(), diesel::result::Error> {
        let now = chrono::Utc::now();
        diesel::update(jobs::table)
            .filter(jobs::id.eq(self.id))
            .set((
                jobs::finished_at.eq(now),
                jobs::status.eq(JobStatus::complete(completion_status.clone())),
            ))
            .execute(conn)
            .await?;
        self.finished_at = Some(now);
        self.status = JobStatus::complete(completion_status);
        Ok(())
    }

    /// Find in-progress jobs that have exceeded the timeout period
    pub async fn find_expired_jobs(
        conn: &mut AsyncPgConnection,
        timeout_seconds: u64,
    ) -> Result<Vec<Job>, diesel::result::Error> {
        // Find jobs that are in progress and started more than timeout_seconds ago
        let timeout_duration = chrono::Duration::seconds(timeout_seconds as i64);
        let cutoff_time = chrono::Utc::now() - timeout_duration;

        // Get jobs to time out
        jobs::table
            .filter(jobs::status.eq(JobStatus::running()))
            .filter(jobs::started_at.lt(cutoff_time))
            .load::<Job>(conn)
            .await
    }

    pub async fn claim_job_for_runner(
        conn: &mut AsyncPgConnection,
        job_id: uuid::Uuid,
        runner_id: uuid::Uuid,
    ) -> Result<usize, diesel::result::Error> {
        diesel::update(jobs::table)
            .filter(jobs::id.eq(job_id))
            .filter(jobs::status.eq(JobStatus(devenv_runner::protocol::JobStatus::Queued)))
            .set((
                jobs::status.eq(JobStatus(devenv_runner::protocol::JobStatus::Running)),
                jobs::runner_id.eq(runner_id),
            ))
            .execute(conn)
            .await
    }

    pub async fn update_job_status(
        conn: &mut AsyncPgConnection,
        job_id: uuid::Uuid,
        status: &JobStatus,
    ) -> Result<(), diesel::result::Error> {
        diesel::update(jobs::table)
            .filter(jobs::id.eq(job_id))
            .set(jobs::status.eq(status))
            .execute(conn)
            .await?;

        Ok(())
    }

    pub async fn find_queued_job_for_platform(
        conn: &mut AsyncPgConnection,
        platform: &Platform,
    ) -> Result<Option<Job>, diesel::result::Error> {
        let job = jobs::table
            .for_update()
            .skip_locked()
            .filter(jobs::status.eq(JobStatus(devenv_runner::protocol::JobStatus::Queued)))
            .filter(jobs::runner_id.is_null())
            .filter(jobs::platform.eq(platform))
            .order_by(jobs::id)
            .first(conn)
            .await
            .optional()?;

        Ok(job)
    }

    /// Check if a job can be retried
    pub fn is_retryable(&self) -> bool {
        matches!(
            &self.status.0,
            devenv_runner::protocol::JobStatus::Complete(status)
                if !matches!(status, devenv_runner::protocol::CompletionStatus::Success)
        )
    }

    /// Retry a non-successful job by creating a new job with the same configuration
    pub async fn retry(&self, conn: &mut AsyncPgConnection) -> Result<Self, diesel::result::Error> {
        // Only completed non-successful jobs can be retried
        if self.is_retryable() {
            // Create a new job with the same parameters but with a new ID, reset status, and link to original job
            let retried_job = diesel::insert_into(jobs::table)
                .values((
                    jobs::id.eq(Uuid::now_v7()),
                    jobs::platform.eq(&self.platform),
                    jobs::status.eq(JobStatus::queued()),
                    jobs::cpus.eq(self.cpus),
                    jobs::memory_mb.eq(self.memory_mb),
                    jobs::previous_job_id.eq(self.id), // Set the previous_job_id to link to the original job
                ))
                .get_result::<Job>(conn)
                .await?;

            // Update the original job to link to the new job
            diesel::update(jobs::table)
                .filter(jobs::id.eq(self.id))
                .set(jobs::retried_job_id.eq(retried_job.id))
                .execute(conn)
                .await?;

            Ok(retried_job)
        } else {
            Err(diesel::result::Error::RollbackTransaction)
        }
    }

    /// Get a job with its associated GitHub data and commit information using a single query
    pub async fn get_with_github_details(
        conn: &mut AsyncPgConnection,
        id: Uuid,
    ) -> Result<
        (
            Self,
            crate::github::model::JobGitHub,
            crate::github::model::GitHubCommit,
        ),
        diesel::result::Error,
    > {
        use crate::schema::{github_commit, jobs, jobs_github};
        use diesel::{ExpressionMethods, QueryDsl, SelectableHelper};

        // Use a single join query to get all data at once
        let (job, github_job, commit) = jobs::table
            .filter(jobs::id.eq(id))
            .inner_join(jobs_github::table.on(jobs_github::job_id.eq(jobs::id)))
            .inner_join(github_commit::table.on(github_commit::id.eq(jobs_github::commit_id)))
            .select((
                Self::as_select(),
                crate::github::model::JobGitHub::as_select(),
                crate::github::model::GitHubCommit::as_select(),
            ))
            .first::<(
                Self,
                crate::github::model::JobGitHub,
                crate::github::model::GitHubCommit,
            )>(conn)
            .await?;

        Ok((job, github_job, commit))
    }

    /// Cancel a job if it's in a cancellable state (queued or running)
    /// Returns Ok(true) if cancelled, Ok(false) if not cancellable, Err on database error
    /// Uses SELECT FOR UPDATE to prevent race conditions
    pub async fn cancel(
        conn: &mut AsyncPgConnection,
        job_id: Uuid,
    ) -> Result<(bool, Option<Self>), diesel::result::Error> {
        use crate::schema::jobs::dsl::*;

        // Use a transaction with SELECT FOR UPDATE to lock the row
        conn.build_transaction()
            .run::<_, diesel::result::Error, _>(|conn| {
                Box::pin(async move {
                    // Lock the job row for update
                    let mut job: Self = jobs.filter(id.eq(job_id)).for_update().first(conn).await?;

                    match job.status.0 {
                        devenv_runner::protocol::JobStatus::Queued => {
                            // Cancel the job
                            job.complete(
                                conn,
                                devenv_runner::protocol::CompletionStatus::Cancelled,
                            )
                            .await?;
                            Ok((true, Some(job)))
                        }
                        devenv_runner::protocol::JobStatus::Running => {
                            // Mark as cancelled (runner will be notified separately)
                            job.complete(
                                conn,
                                devenv_runner::protocol::CompletionStatus::Cancelled,
                            )
                            .await?;
                            Ok((true, Some(job)))
                        }
                        _ => Ok((false, Some(job))), // Job is not in a cancellable state
                    }
                })
            })
            .await
    }

    /// Check if a job can be cancelled (must be queued or running)
    pub fn is_cancellable(&self) -> bool {
        matches!(
            self.status.0,
            devenv_runner::protocol::JobStatus::Queued
                | devenv_runner::protocol::JobStatus::Running
        )
    }

    /// Build VM configuration from job parameters
    pub fn to_vm_config(&self) -> devenv_runner::protocol::VM {
        devenv_runner::protocol::VM {
            cpu_count: self.cpus as usize,
            memory_size_mb: self.memory_mb as u64,
            platform: self.platform.clone().into(),
        }
    }

    /// Generate the log URL for this job
    pub fn log_url(&self, logger_base_url: &str) -> String {
        format!("{}/{}", logger_base_url, self.id)
    }
}
