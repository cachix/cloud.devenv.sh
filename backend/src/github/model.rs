use crate::config::AppState;
use crate::job::model::Job;
use crate::schema::{
    github_commit, github_installation, github_instance, github_owner, github_repo, jobs,
    jobs_github,
};
use async_trait::async_trait;
use devenv_runner::protocol;
use diesel::prelude::*;
use diesel_async::RunQueryDsl;
use eyre::Result;
use serde::Deserialize;
use serde::Serialize;
use utoipa::ToSchema;

#[derive(Queryable, Selectable, Identifiable)]
#[diesel(table_name = github_instance)]
pub struct GithubInstance {
    pub id: i32,
    pub host: String,
}

#[derive(Queryable, Selectable, Identifiable, Insertable, AsChangeset)]
#[diesel(table_name = github_installation)]
pub struct GithubInstallation {
    pub id: i64,
    pub owner_id: i64,
    pub disabled: bool,
}

#[derive(Queryable, Selectable, Identifiable, Insertable, AsChangeset)]
#[diesel(table_name = github_owner)]
pub struct GithubOwner {
    pub id: i64,
    pub login: String,
    pub name: String,
    pub instance_id: i32,
    pub is_user: bool,
}

impl GithubOwner {
    pub async fn get_by_login(
        conn: &mut diesel_async::AsyncPgConnection,
        login: &str,
    ) -> crate::error::Result<Self> {
        let owner = github_owner::table
            .filter(github_owner::login.eq(login))
            .select(GithubOwner::as_select())
            .first(conn)
            .await?;
        Ok(owner)
    }

    /// Insert or update a GitHub owner
    pub async fn upsert(conn: &mut diesel_async::AsyncPgConnection, owner: Self) -> Result<()> {
        diesel::insert_into(github_owner::table)
            .values(&owner)
            .on_conflict(github_owner::id)
            .do_update()
            .set(&owner)
            .execute(conn)
            .await?;
        Ok(())
    }
}

impl GithubInstallation {
    pub async fn disable(
        conn: &mut diesel_async::AsyncPgConnection,
        installation_id: i64,
        disabled: bool,
    ) -> crate::error::Result<()> {
        diesel::update(github_installation::table)
            .filter(github_installation::id.eq(installation_id))
            .set(github_installation::disabled.eq(disabled))
            .execute(conn)
            .await?;
        Ok(())
    }

    pub async fn get_for_owner_id(
        conn: &mut diesel_async::AsyncPgConnection,
        owner_id: i64,
    ) -> diesel::result::QueryResult<Self> {
        github_installation::table
            .filter(github_installation::owner_id.eq(owner_id))
            .filter(github_installation::disabled.eq(false))
            .select(GithubInstallation::as_select())
            .first(conn)
            .await
    }

    pub fn installation_id(&self) -> octocrab::models::InstallationId {
        octocrab::models::InstallationId(self.id as u64)
    }

    /// Insert or update a GitHub installation
    pub async fn upsert(
        conn: &mut diesel_async::AsyncPgConnection,
        installation: Self,
    ) -> Result<()> {
        diesel::insert_into(github_installation::table)
            .values(&installation)
            .on_conflict(github_installation::id)
            .do_update()
            .set(github_installation::disabled.eq(installation.disabled))
            .execute(conn)
            .await?;
        Ok(())
    }
}

#[derive(Queryable, Selectable, Identifiable, Associations, Insertable, AsChangeset)]
#[diesel(belongs_to(GithubOwner, foreign_key = id))]
#[diesel(table_name = github_repo)]
pub struct GitHubRepo {
    pub id: i64,
    pub name: String,
    pub is_private: bool,
    pub owner_id: i64,
    pub disabled: bool,
    pub generate_pr: Option<String>,
}

impl GitHubRepo {
    pub async fn get_by_owner_and_name(
        conn: &mut diesel_async::AsyncPgConnection,
        owner_id: i64,
        name: &str,
    ) -> crate::error::Result<Self> {
        let repo = github_repo::table
            .filter(github_repo::owner_id.eq(owner_id))
            .filter(github_repo::name.eq(name))
            .select(GitHubRepo::as_select())
            .first(conn)
            .await?;
        Ok(repo)
    }

    pub async fn update_generate_pr(
        conn: &mut diesel_async::AsyncPgConnection,
        owner_id: i64,
        repo_name: &str,
        html_url: &Option<String>,
    ) -> crate::error::Result<()> {
        diesel::update(github_repo::table)
            .filter(github_repo::owner_id.eq(owner_id))
            .filter(github_repo::name.eq(repo_name))
            .set(github_repo::generate_pr.eq(html_url))
            .execute(conn)
            .await?;

        Ok(())
    }

    /// Insert or update a GitHub repo
    pub async fn upsert(conn: &mut diesel_async::AsyncPgConnection, repo: Self) -> Result<()> {
        diesel::insert_into(github_repo::table)
            .values(&repo)
            .on_conflict(github_repo::id)
            .do_update()
            .set(&repo)
            .execute(conn)
            .await?;
        Ok(())
    }

    /// Create or update a repo from webhook data
    pub async fn create_from_webhook(
        conn: &mut diesel_async::AsyncPgConnection,
        repo_id: i64,
        name: String,
        is_private: bool,
        owner_id: i64,
    ) -> Result<Self> {
        let repo = GitHubRepo {
            id: repo_id,
            name,
            is_private,
            owner_id,
            disabled: false,
            generate_pr: None,
        };

        let result = diesel::insert_into(github_repo::table)
            .values(&repo)
            .on_conflict(github_repo::id)
            .do_update()
            .set((
                github_repo::name.eq(&repo.name),
                github_repo::is_private.eq(repo.is_private),
                github_repo::disabled.eq(false),
            ))
            .returning(GitHubRepo::as_returning())
            .get_result(conn)
            .await?;
        Ok(result)
    }

    /// Mark a repo as disabled
    pub async fn disable(conn: &mut diesel_async::AsyncPgConnection, repo_id: i64) -> Result<()> {
        diesel::update(github_repo::table)
            .filter(github_repo::id.eq(repo_id))
            .set(github_repo::disabled.eq(true))
            .execute(conn)
            .await?;
        Ok(())
    }
}

#[derive(
    Queryable,
    Selectable,
    Identifiable,
    Associations,
    Insertable,
    AsChangeset,
    Serialize,
    Deserialize,
    ToSchema,
    Clone,
    Debug,
)]
#[diesel(belongs_to(GitHubRepo, foreign_key = id))]
#[diesel(table_name = github_commit)]
pub struct GitHubCommit {
    pub id: uuid::Uuid,
    pub rev: String,
    #[diesel(column_name = git_ref)]
    pub r#ref: String,
    pub repo_id: i64,
    pub author: String,
    pub message: String,
}

impl GitHubCommit {
    pub async fn create_job(
        &self,
        app_state: AppState,
        vm_config: devenv_runner::protocol::VM,
    ) -> Result<JobGitHub> {
        <JobGitHub as SourceControlIntegration>::create_job(
            self.id,
            &self.rev,
            self.repo_id,
            app_state,
            vm_config,
        )
        .await
    }

    pub async fn get_by_id(
        conn: &mut diesel_async::AsyncPgConnection,
        id: uuid::Uuid,
    ) -> crate::error::Result<Self> {
        use crate::schema::github_commit;
        use diesel::ExpressionMethods;
        use diesel::QueryDsl;
        use diesel::SelectableHelper;
        use diesel_async::RunQueryDsl;

        let commit = github_commit::table
            .filter(github_commit::id.eq(id))
            .select(GitHubCommit::as_select())
            .first(conn)
            .await?;

        Ok(commit)
    }

    pub async fn get_latest_by_repo_id(
        conn: &mut diesel_async::AsyncPgConnection,
        repo_id: i64,
    ) -> diesel::result::QueryResult<Self> {
        github_commit::table
            .filter(github_commit::repo_id.eq(repo_id))
            .order_by(github_commit::id.desc()) // UUIDv7 is time ordered
            .limit(1)
            .select(GitHubCommit::as_select())
            .first::<GitHubCommit>(conn)
            .await
    }

    pub async fn get_jobs_by_commit_id(
        conn: &mut diesel_async::AsyncPgConnection,
        commit_id: uuid::Uuid,
    ) -> Result<Vec<(JobGitHub, crate::job::model::Job)>> {
        let job_pairs = jobs_github::table
            .inner_join(
                crate::schema::jobs::table.on(jobs_github::job_id.eq(crate::schema::jobs::id)),
            )
            .filter(jobs_github::commit_id.eq(commit_id))
            .order_by(crate::schema::jobs::platform)
            .select((JobGitHub::as_select(), crate::job::model::Job::as_select()))
            .load::<(JobGitHub, crate::job::model::Job)>(conn)
            .await?;

        Ok(job_pairs)
    }

    /// Get commit by repo and rev
    pub async fn get_by_repo_and_rev(
        conn: &mut diesel_async::AsyncPgConnection,
        repo_id: i64,
        rev: &str,
    ) -> Result<Self> {
        let commit = github_commit::table
            .filter(github_commit::repo_id.eq(repo_id))
            .filter(github_commit::rev.eq(rev))
            .select(GitHubCommit::as_select())
            .first(conn)
            .await?;
        Ok(commit)
    }

    /// Create a new commit
    pub async fn create(conn: &mut diesel_async::AsyncPgConnection, commit: Self) -> Result<()> {
        diesel::insert_into(github_commit::table)
            .values(&commit)
            .execute(conn)
            .await?;
        Ok(())
    }

    /// Get commits by repo ordered by newest first
    pub async fn get_by_repo_ordered(
        conn: &mut diesel_async::AsyncPgConnection,
        repo_id: i64,
    ) -> Result<Vec<Self>> {
        let commits = github_commit::table
            .filter(github_commit::repo_id.eq(repo_id))
            .order_by(github_commit::id.desc()) // UUIDv7 is time ordered
            .select(GitHubCommit::as_select())
            .load::<GitHubCommit>(conn)
            .await?;
        Ok(commits)
    }
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct Commit {
    pub owner: String,
    pub repo: String,
    pub rev: String,
    pub r#ref: String,
    pub author: String,
    pub message: String,
    pub jobs: Vec<crate::job::serve::JobResponse>,
}

#[derive(
    Debug,
    Clone,
    Queryable,
    Selectable,
    Serialize,
    Deserialize,
    utoipa::ToSchema,
    Default,
    Identifiable,
    Associations,
)]
#[diesel(belongs_to(GitHubCommit, foreign_key = commit_id))]
#[diesel(belongs_to(crate::job::model::Job, foreign_key = job_id))]
#[diesel(primary_key(job_id))]
#[diesel(table_name = jobs_github)]
pub struct JobGitHub {
    pub job_id: uuid::Uuid,
    pub commit_id: uuid::Uuid,
    pub check_run_id: i64,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct OwnerWithRepos {
    pub id: i64,
    pub login: String,
    pub name: String,
    pub is_user: bool,
    pub repos: Vec<RepoInfo>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct RepoInfo {
    pub id: i64,
    pub name: String,
    pub is_private: bool,
    pub generate_pr: Option<String>,
    pub latest_commit: Option<Commit>,
}

#[async_trait]
pub trait SourceControlIntegration {
    /// Gets a specific job by ID
    async fn get_job_by_id(
        conn: &mut diesel_async::AsyncPgConnection,
        id: uuid::Uuid,
    ) -> Result<Self>
    where
        Self: Sized;

    /// Updates job status in the source control system
    async fn update_status(
        app_state: AppState,
        status: protocol::JobStatus,
        id: uuid::Uuid,
    ) -> Result<()>;

    /// Creates a job for the CI/CD system
    async fn create_job(
        commit_id: uuid::Uuid,
        rev: &str,
        repo_id: i64,
        app_state: AppState,
        vm_config: devenv_runner::protocol::VM,
    ) -> Result<Self>
    where
        Self: Sized;
}

impl JobGitHub {
    // Helper method to get a GitHub installation client for an owner
    pub fn get_installation_client(
        app_state: &AppState,
        installation_id: i64,
    ) -> Result<octocrab::Octocrab> {
        let client = app_state
            .github
            .installation(octocrab::models::InstallationId(installation_id as u64))?;
        Ok(client)
    }

    async fn get_repo_and_owner(
        &self,
        conn: &mut diesel_async::AsyncPgConnection,
    ) -> Result<(GitHubRepo, GithubOwner)> {
        let commit: GitHubCommit = github_commit::table
            .filter(github_commit::id.eq(self.commit_id))
            .select(GitHubCommit::as_select())
            .first(conn)
            .await?;

        let repo: GitHubRepo = github_repo::table
            .filter(github_repo::id.eq(commit.repo_id))
            .select(GitHubRepo::as_select())
            .first(conn)
            .await?;

        let owner: GithubOwner = github_owner::table
            .filter(github_owner::id.eq(repo.owner_id))
            .select(GithubOwner::as_select())
            .first(conn)
            .await?;

        Ok((repo, owner))
    }

    pub async fn get_owners_with_repos(
        conn: &mut diesel_async::AsyncPgConnection,
    ) -> Result<Vec<(GithubOwner, GitHubRepo)>> {
        let owners_with_repos = github_owner::table
            .inner_join(
                github_installation::table.on(github_owner::id.eq(github_installation::owner_id)),
            )
            .inner_join(github_repo::table.on(github_owner::id.eq(github_repo::owner_id)))
            .filter(github_installation::disabled.eq(false))
            .filter(github_repo::disabled.eq(false))
            .select((GithubOwner::as_select(), GitHubRepo::as_select()))
            .load::<(GithubOwner, GitHubRepo)>(conn)
            .await?
            .into_iter()
            .collect();

        Ok(owners_with_repos)
    }

    pub async fn get_jobs_for_repo(
        conn: &mut diesel_async::AsyncPgConnection,
        repo_id: i64,
    ) -> Result<Vec<(JobGitHub, crate::job::model::Job)>> {
        let job_pairs = jobs_github::table
            .inner_join(github_commit::table.on(jobs_github::commit_id.eq(github_commit::id)))
            .inner_join(
                crate::schema::jobs::table.on(jobs_github::job_id.eq(crate::schema::jobs::id)),
            )
            .filter(github_commit::repo_id.eq(repo_id))
            .order_by(crate::schema::jobs::platform)
            .select((JobGitHub::as_select(), crate::job::model::Job::as_select()))
            .load::<(JobGitHub, crate::job::model::Job)>(conn)
            .await?;

        Ok(job_pairs)
    }

    pub async fn get_all_jobs_for_commit(
        conn: &mut diesel_async::AsyncPgConnection,
        commit_id: uuid::Uuid,
    ) -> Result<Vec<(crate::job::model::Job, JobGitHub)>> {
        let jobs = jobs_github::table
            .inner_join(
                crate::schema::jobs::table.on(jobs_github::job_id.eq(crate::schema::jobs::id)),
            )
            .filter(jobs_github::commit_id.eq(commit_id))
            .order_by(crate::schema::jobs::platform)
            .select((crate::job::model::Job::as_select(), JobGitHub::as_select()))
            .load::<(crate::job::model::Job, JobGitHub)>(conn)
            .await?;

        Ok(jobs)
    }

    /// Get GitHub data for a specific job
    pub async fn get_for_job(
        conn: &mut diesel_async::AsyncPgConnection,
        job: &crate::job::model::Job,
    ) -> Result<Self> {
        use diesel_async::RunQueryDsl;

        jobs_github::table
            .filter(jobs_github::job_id.eq(job.id))
            .first::<Self>(conn)
            .await
            .map_err(Into::into)
    }

    /// Create a new JobGitHub record with a check run for a job
    pub async fn create_with_check_run(
        conn: &mut diesel_async::AsyncPgConnection,
        app_state: &crate::config::AppState,
        job: &crate::job::model::Job,
        commit: &GitHubCommit,
    ) -> Result<Self> {
        // Create the check run via GitHub API
        let check_run_id = Self::create_github_check_run(conn, app_state, job, commit).await?;

        // Create the JobGitHub record with the check_run_id
        let job_github = diesel::insert_into(jobs_github::table)
            .values((
                jobs_github::job_id.eq(job.id),
                jobs_github::commit_id.eq(commit.id),
                jobs_github::check_run_id.eq(check_run_id),
            ))
            .get_result::<JobGitHub>(conn)
            .await?;

        Ok(job_github)
    }

    /// Create a GitHub check run for an existing job and return the updated JobGitHub
    pub async fn create_check_run_for_job(
        self,
        conn: &mut diesel_async::AsyncPgConnection,
        app_state: &crate::config::AppState,
        job: &crate::job::model::Job,
        commit: &GitHubCommit,
    ) -> Result<Self> {
        // Create the check run via GitHub API
        let check_run_id = Self::create_github_check_run(conn, app_state, job, commit).await?;

        // Update the existing JobGitHub record with the check_run_id
        let updated_github = diesel::update(jobs_github::table)
            .filter(jobs_github::job_id.eq(job.id))
            .set(jobs_github::check_run_id.eq(check_run_id))
            .returning(JobGitHub::as_returning())
            .get_result(conn)
            .await?;

        Ok(updated_github)
    }

    /// Helper to create a GitHub check run and return the check_run_id
    async fn create_github_check_run(
        conn: &mut diesel_async::AsyncPgConnection,
        app_state: &crate::config::AppState,
        job: &crate::job::model::Job,
        commit: &GitHubCommit,
    ) -> Result<i64> {
        // Get repo and owner
        let repo: GitHubRepo = github_repo::table
            .filter(github_repo::id.eq(commit.repo_id))
            .select(GitHubRepo::as_select())
            .first(conn)
            .await?;
        let owner: GithubOwner = github_owner::table
            .filter(github_owner::id.eq(repo.owner_id))
            .select(GithubOwner::as_select())
            .first(conn)
            .await?;

        // Get installation client
        let installation = GithubInstallation::get_for_owner_id(conn, owner.id).await?;
        let installation_client = Self::get_installation_client(app_state, installation.id)?;

        // Create check run
        let checks = installation_client.checks(&owner.login, &repo.name);
        let details_url = format!(
            "{}/github/{}/{}#{}",
            app_state.config.base_url, owner.login, repo.name, job.id
        );

        let check_run = checks
            .create_check_run(format!("devenv ({})", job.platform), &commit.rev)
            .details_url(details_url)
            .external_id(job.id)
            .status(octocrab::params::checks::CheckRunStatus::Queued)
            .send()
            .await?;

        Ok(check_run.id.0 as i64)
    }
}

#[async_trait]
impl SourceControlIntegration for JobGitHub {
    async fn get_job_by_id(
        conn: &mut diesel_async::AsyncPgConnection,
        id: uuid::Uuid,
    ) -> Result<Self> {
        use crate::schema::jobs_github;
        use diesel_async::RunQueryDsl;

        // Get the GitHub job directly from the database
        let job_github = jobs_github::table
            .filter(jobs_github::job_id.eq(id))
            .first::<Self>(conn)
            .await?;

        Ok(job_github)
    }

    async fn update_status(
        app_state: AppState,
        status: protocol::JobStatus,
        id: uuid::Uuid,
    ) -> Result<()> {
        let conn = &mut app_state.pool.get().await?;

        // Get the GitHub job directly
        let job_github = Self::get_job_by_id(conn, id).await?;

        let (repo, owner) = job_github.get_repo_and_owner(conn).await?;
        // Get an installation-authenticated client for the GitHub App
        let installation = GithubInstallation::get_for_owner_id(conn, owner.id).await?;
        let installation_client = Self::get_installation_client(&app_state, installation.id)?;

        let checks = installation_client.checks(&owner.login, &repo.name);
        let check =
            checks.update_check_run(octocrab::models::CheckRunId(job_github.check_run_id as u64));
        match status {
            protocol::JobStatus::Queued => {}
            protocol::JobStatus::Running => {
                let now = chrono::Utc::now();
                check
                    .status(octocrab::params::checks::CheckRunStatus::InProgress)
                    .started_at(now)
                    .send()
                    .await?;
                diesel::update(jobs::table)
                    .filter(jobs::id.eq(job_github.job_id))
                    .set(jobs::started_at.eq(now))
                    .execute(conn)
                    .await?;
            }
            protocol::JobStatus::Complete(completion_status) => {
                let now = chrono::Utc::now();
                let conclusion = match &completion_status {
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
                diesel::update(jobs::table)
                    .filter(jobs::id.eq(job_github.job_id))
                    .set(jobs::finished_at.eq(now))
                    .execute(conn)
                    .await?;
            }
        }
        Ok(())
    }

    async fn create_job(
        commit_id: uuid::Uuid,
        rev: &str,
        repo_id: i64,
        app_state: AppState,
        vm_config: devenv_runner::protocol::VM,
    ) -> Result<Self> {
        let conn = &mut app_state.pool.get().await?;

        // Convert VM config platform to job platform
        // Get platform enum for job creation and formatting
        let job_platform = match vm_config.platform {
            devenv_runner::protocol::Platform::X86_64Linux => {
                crate::job::model::Platform::X86_64Linux
            }
            devenv_runner::protocol::Platform::AArch64Darwin => {
                crate::job::model::Platform::AArch64Darwin
            }
        };

        // Create job with specified VM configuration
        let job = Job::new(
            conn,
            job_platform,
            Some(vm_config.cpu_count as i32),
            Some(vm_config.memory_size_mb as i64),
        )
        .await?;

        let repo: GitHubRepo = github_repo::table
            .filter(github_repo::id.eq(repo_id))
            .select(GitHubRepo::as_select())
            .first(conn)
            .await?;
        let owner: GithubOwner = github_owner::table
            .filter(github_owner::id.eq(repo.owner_id))
            .select(GithubOwner::as_select())
            .first(conn)
            .await?;

        // Get an installation-authenticated client for the GitHub App
        let installation = GithubInstallation::get_for_owner_id(conn, owner.id).await?;
        let installation_client = Self::get_installation_client(&app_state, installation.id)?;

        let checks = installation_client.checks(&owner.login, &repo.name);
        // Create a details URL with a fragment pointing to the job UI
        // Format: https://cloud.devenv.sh/github/{owner}/{repo}#{job_id}
        let details_url = format!(
            "{}/github/{}/{}#{}",
            app_state.config.base_url, owner.login, repo.name, job.id
        );

        let check_run = checks
            .create_check_run(format!("devenv ({})", job.platform), rev)
            .details_url(details_url)
            .external_id(job.id)
            .status(octocrab::params::checks::CheckRunStatus::Queued)
            .send()
            .await?;

        let githubjob = diesel::insert_into(jobs_github::table)
            .values((
                jobs_github::commit_id.eq(commit_id),
                jobs_github::check_run_id.eq(check_run.id.0 as i64),
                jobs_github::job_id.eq(job.id),
            ))
            .returning(JobGitHub::as_returning())
            .get_result(conn)
            .await?;

        // Retrieve job from database to get full job::model::Job type
        let job_for_runner = crate::job::model::Job::get_by_id(conn, job.id).await?;

        // Notify all connected runners about the new job
        crate::runner::serve::notify_runners_about_job(&app_state, &job_for_runner).await;

        Ok(githubjob)
    }
}

/// Helper struct for webhook processing
pub struct WebhookProcessor;

impl WebhookProcessor {
    /// Verify webhook signature
    pub fn verify_webhook_signature(body: &[u8], signature: &str, secret: &str) -> Result<()> {
        use hmac::{Hmac, Mac};
        use sha2::Sha256;

        type HmacSha256 = Hmac<Sha256>;

        let signature = signature
            .strip_prefix("sha256=")
            .ok_or(eyre::eyre!("Invalid signature format"))?;

        let mut mac = HmacSha256::new_from_slice(secret.as_bytes())?;
        mac.update(body);

        let signature_bytes = hex::decode(signature)?;
        let signature_array =
            hmac::digest::Output::<Sha256>::from_slice(&signature_bytes).to_owned();

        // Use constant-time comparison from hmac crate
        use hmac::digest::CtOutput;
        if mac.finalize() == CtOutput::new(signature_array) {
            Ok(())
        } else {
            Err(eyre::eyre!("Invalid signature"))
        }
    }
}
