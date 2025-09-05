use crate::auth::BetaUser;
use crate::config::AppState;
use crate::error::Result;
use crate::github::model::{
    Commit, GitHubCommit, GitHubRepo, GithubInstallation, GithubOwner, OwnerWithRepos, RepoInfo,
    WebhookProcessor,
};
use crate::schema::github_owner;
use axum::body::Bytes;
use axum::{Json, extract::State};
use diesel::prelude::*;
use diesel_async::RunQueryDsl;
use eyre::{OptionExt, eyre};
use octocrab::models::webhook_events::payload::{
    InstallationWebhookEventAction, PullRequestWebhookEventAction,
};
use octocrab::models::webhook_events::{EventInstallation, WebhookEvent, WebhookEventPayload};
use utoipa_axum::{router::OpenApiRouter, routes};

use super::model::JobGitHub;

#[utoipa::path(get, path = "/repos", responses((status = OK, body = Vec<OwnerWithRepos>)))]
async fn get_repos(
    State(app_state): State<AppState>,
    _user: BetaUser,
) -> Result<Json<Vec<OwnerWithRepos>>> {
    let conn = &mut app_state.pool.get().await?;

    // Fetch all owners with active installations
    let owners_with_repos = JobGitHub::get_owners_with_repos(conn).await?;

    // Group repos by owner
    let mut owner_map: std::collections::HashMap<i64, (GithubOwner, Vec<GitHubRepo>)> =
        std::collections::HashMap::new();

    for (owner, repo) in owners_with_repos {
        owner_map
            .entry(owner.id)
            .or_insert_with(|| (owner, Vec::new()))
            .1
            .push(repo);
    }

    // Fetch the latest commit and all jobs for each repo
    let mut repo_latest_commits: std::collections::HashMap<
        i64,
        (GitHubCommit, Vec<(crate::job::model::Job, JobGitHub)>),
    > = std::collections::HashMap::new();

    // Get all repo IDs
    let repo_ids: Vec<i64> = owner_map
        .values()
        .flat_map(|(_, repos)| repos.iter().map(|r| r.id))
        .collect();

    // For each repo, find the latest commit
    for repo_id in repo_ids {
        if let Ok(latest_commit) = GitHubCommit::get_latest_by_repo_id(conn, repo_id).await {
            // Find all jobs for this commit
            let all_jobs = JobGitHub::get_all_jobs_for_commit(conn, latest_commit.id)
                .await
                .unwrap_or_default();

            repo_latest_commits.insert(repo_id, (latest_commit, all_jobs));
        }
    }

    // Convert to OwnerWithRepos structs
    let result = owner_map
        .into_values()
        .map(|(owner, repos)| {
            let repo_infos = repos
                .into_iter()
                .map(|repo| {
                    // Get latest commit and job info for this repo
                    let latest_commit_info =
                        repo_latest_commits.get(&repo.id).map(|(commit, all_jobs)| {
                            let jobs = all_jobs
                                .iter()
                                .map(|(job, job_github)| {
                                    let log_url =
                                        format!("{}/{}", app_state.config.logger_url, job.id);
                                    JobResponse {
                                        github: job_github.clone(),
                                        job: job.clone(),
                                        commit: commit.clone(),
                                        log_url,
                                    }
                                })
                                .collect();

                            Commit {
                                owner: owner.login.clone(),
                                repo: repo.name.clone(),
                                rev: commit.rev.clone(),
                                r#ref: commit.r#ref.clone(),
                                author: commit.author.clone(),
                                message: commit.message.clone(),
                                jobs,
                            }
                        });

                    RepoInfo {
                        id: repo.id,
                        name: repo.name,
                        is_private: repo.is_private,
                        generate_pr: repo.generate_pr,
                        latest_commit: latest_commit_info,
                    }
                })
                .collect();

            OwnerWithRepos {
                id: owner.id,
                login: owner.login,
                name: owner.name,
                is_user: owner.is_user,
                repos: repo_infos,
            }
        })
        .collect();

    Ok(Json(result))
}

// Using the JobResponse from job/serve.rs
use crate::job::serve::JobResponse;

#[utoipa::path(
    get,
    path = "/{owner}/{repo}/{rev}",
    params(
        ("owner" = String, Path, description = "The repository owner"),
        ("repo" = String, Path, description = "The repository name"),
        ("rev" = String, Path, description = "The commit revision hash")
    ),
    responses((status = OK, body = Commit))
)]
async fn get_rev(
    State(app_state): State<AppState>,
    _user: BetaUser,
    axum::extract::Path((owner_login, repo_name, rev)): axum::extract::Path<(
        String,
        String,
        String,
    )>,
) -> Result<Json<Commit>> {
    let conn = &mut app_state.pool.get().await?;
    let owner = GithubOwner::get_by_login(conn, &owner_login).await?;
    let repo = GitHubRepo::get_by_owner_and_name(conn, owner.id, &repo_name).await?;
    let commit = GitHubCommit::get_by_repo_and_rev(conn, repo.id, &rev).await?;
    // Fetch JobGitHub entries and Jobs in a single query using a join
    // Get all the job data
    let job_pairs = GitHubCommit::get_jobs_by_commit_id(conn, commit.id).await?;

    // Create the JobResponse objects with commit info
    let job_responses: Vec<JobResponse> = job_pairs
        .into_iter()
        .map(|(github, job)| {
            // Generate a log URL for this job
            let log_url = format!("{}/{}", app_state.config.logger_url, job.id);
            JobResponse {
                github,
                job,
                commit: commit.clone(),
                log_url,
            }
        })
        .collect();

    Ok(Json(Commit {
        owner: owner_login,
        repo: repo_name,
        rev: commit.rev,
        r#ref: commit.r#ref,
        author: commit.author,
        message: commit.message,
        jobs: job_responses,
    }))
}

#[utoipa::path(post, path = "/webhook", responses((status = OK, body = ())))]
#[tracing::instrument(skip_all, fields(body=%serde_json::to_string_pretty(&serde_json::from_slice::<serde_json::Value>(&body).unwrap_or_default()).unwrap()))]
async fn webhook(
    State(app_state): State<AppState>,
    headers: axum::http::HeaderMap,
    body: Bytes,
) -> Result<()> {
    let event_name = headers
        .get("X-GitHub-Event")
        .map(|h| h.to_str().unwrap_or_default())
        .unwrap_or_default();
    let signature = headers
        .get("X-Hub-Signature-256")
        .map(|h| h.to_str().unwrap_or_default())
        .unwrap_or_default();

    // Verify webhook signature using the model method
    let webhook_secret = app_state
        .secrets
        .github_webhook_secret
        .as_ref()
        .ok_or_else(|| eyre!("GitHub webhook secret not configured"))?;

    WebhookProcessor::verify_webhook_signature(&body, signature, webhook_secret)?;

    let event: WebhookEvent = WebhookEvent::try_from_header_and_body(event_name, &body)?;

    let conn = &mut app_state.pool.get().await?;

    let installation = event
        .installation
        .ok_or_eyre("could not get installation")?;

    let installation_id = match &installation {
        EventInstallation::Full(installation) => installation.id,
        EventInstallation::Minimal(id) => id.id,
    };

    match event.specific {
        WebhookEventPayload::Installation(installation_payload) => {
            let account = match installation {
                EventInstallation::Full(installation) => installation.account,
                EventInstallation::Minimal(_) => {
                    panic!("can't happen")
                }
            };
            match installation_payload.action {
                InstallationWebhookEventAction::Created => {
                    let owner = GithubOwner {
                        id: account.id.0 as i64,
                        login: account.login.clone(),
                        name: account.login.clone(),
                        is_user: account.r#type == "User",
                        instance_id: 1,
                    };

                    GithubOwner::upsert(conn, owner).await?;

                    let installation = GithubInstallation {
                        id: installation_id.0 as i64,
                        owner_id: account.id.0 as i64,
                        disabled: false,
                    };
                    GithubInstallation::upsert(conn, installation).await?;

                    if let Some(event_repositories) = installation_payload.repositories {
                        for event_repo in event_repositories {
                            let repo = GitHubRepo {
                                id: event_repo.id.into_inner() as i64,
                                name: event_repo.name,
                                is_private: event_repo.private,
                                owner_id: account.id.0 as i64,
                                disabled: false,
                                generate_pr: None,
                            };
                            GitHubRepo::upsert(conn, repo).await?;
                        }
                    }
                }
                InstallationWebhookEventAction::Deleted
                | InstallationWebhookEventAction::Suspend => {
                    GithubInstallation::disable(conn, installation_id.0 as i64, true).await?;
                }
                InstallationWebhookEventAction::Unsuspend => {
                    GithubInstallation::disable(conn, installation_id.0 as i64, false).await?;
                }
                InstallationWebhookEventAction::NewPermissionsAccepted => {}
                _ => {}
            }
        }
        WebhookEventPayload::InstallationRepositories(installation_repos) => {
            let account = if let EventInstallation::Full(installation) = installation {
                installation.account
            } else {
                panic!("can't happen")
            };

            for repo in installation_repos.repositories_added {
                GitHubRepo::create_from_webhook(
                    conn,
                    repo.id.into_inner() as i64,
                    repo.name,
                    repo.private,
                    account.id.0 as i64,
                )
                .await?;
            }

            for repo in installation_repos.repositories_removed {
                GitHubRepo::disable(conn, repo.id.into_inner() as i64).await?;
            }
        }
        WebhookEventPayload::Push(push) => {
            let repository = event.repository.expect("push should have a repo");
            let owner_id = repository
                .owner
                .as_ref()
                .expect("push should have a owner")
                .id
                .0 as i64;
            let owner_login = repository
                .owner
                .as_ref()
                .expect("push should have a owner")
                .login
                .clone();
            let repo_name = repository.name.clone();
            // Get the installation for this repository's owner
            let conn = &mut app_state.pool.get().await?;
            let db_owner: GithubOwner = github_owner::table
                .filter(github_owner::id.eq(owner_id))
                .first(conn)
                .await?;

            let installation = GithubInstallation::get_for_owner_id(conn, db_owner.id).await?;

            // Get an installation-authenticated client
            let installation_client =
                JobGitHub::get_installation_client(&app_state, installation.id)?;

            // Check if devenv.nix exists
            let content_items = installation_client
                .repos(owner_login.clone(), repo_name.clone())
                .get_content()
                .path("devenv.nix")
                .r#ref(&push.r#ref)
                .send()
                .await?;

            if !content_items.items.is_empty() {
                // Extract reference name without refs/heads/ prefix
                let ref_name = push.r#ref.trim_start_matches("refs/heads/").to_string();

                // Get the author handle and message from the latest commit
                let (author, message) = if let Some(commit) = push.commits.get(0) {
                    (
                        commit
                            .author
                            .username
                            .clone()
                            .unwrap_or_else(|| String::from("Unknown")),
                        commit.message.clone(),
                    )
                } else {
                    (String::from("Unknown"), String::from("No message provided"))
                };

                // Create the commit record
                let github_commit = GitHubCommit {
                    id: uuid::Uuid::now_v7(),
                    rev: push.after,
                    r#ref: ref_name,
                    repo_id: repository.id.into_inner() as i64,
                    author,
                    message,
                };

                // Insert the commit into the database
                GitHubCommit::create(conn, github_commit.clone()).await?;

                // Try to fetch devenv.yaml to determine VM configurations
                let devenv_yaml_content = match installation_client
                    .repos(owner_login.clone(), repo_name.clone())
                    .get_content()
                    .path("devenv.yaml")
                    .r#ref(&push.r#ref)
                    .send()
                    .await
                {
                    Ok(content) if !content.items.is_empty() => {
                        if let Some(content) = content.items[0].decoded_content() {
                            Some(content)
                        } else {
                            tracing::warn!("Failed to decode devenv.yaml content");
                            None
                        }
                    }
                    _ => None,
                };

                // Parse devenv.yaml and get VM configurations
                let yaml_str = devenv_yaml_content.as_deref().unwrap_or("");
                let cloud_config = crate::runner::cloudconfig::FinalCloud::new(yaml_str)
                    .map_err(|e| eyre!("Failed to parse devenv.yaml: {}", e))?;
                let vms = cloud_config.into_vms();

                // Create a job for each VM configuration
                for vm in vms {
                    github_commit.create_job(app_state.clone(), vm).await?;
                }
            }
        }
        WebhookEventPayload::PullRequest(pr) => match pr.action {
            PullRequestWebhookEventAction::Synchronize => {
                let ref_field = pr.pull_request.head.ref_field;
                // Get the head repository where the branch exists
                let repo = pr
                    .pull_request
                    .head
                    .repo
                    .ok_or_eyre("could not get head repository from pull request")?;
                let owner_name = repo
                    .owner
                    .ok_or_eyre("could not get repository owner")?
                    .login;
                // Get the installation for this repository's owner
                let conn = &mut app_state.pool.get().await?;
                let db_owner = GithubOwner::get_by_login(conn, &owner_name).await?;
                let installation = GithubInstallation::get_for_owner_id(conn, db_owner.id).await?;

                // Get an installation-authenticated client
                let installation_client =
                    JobGitHub::get_installation_client(&app_state, installation.id)?;

                // Check if devenv.nix exists
                let content_items = installation_client
                    .repos(owner_name.clone(), repo.name.clone())
                    .get_content()
                    .path("devenv.nix")
                    .r#ref(&ref_field)
                    .send()
                    .await?;

                if !content_items.items.is_empty() {
                    // Get author and commit message from PR
                    let (author, message) = (
                        pr.pull_request
                            .user
                            .as_ref()
                            .map(|user| user.login.clone())
                            .unwrap_or_else(|| String::from("Unknown")),
                        pr.pull_request
                            .title
                            .clone()
                            .unwrap_or_else(|| String::from("No message provided")),
                    );

                    let github_commit = GitHubCommit {
                        id: uuid::Uuid::now_v7(),
                        rev: pr.pull_request.head.sha,
                        r#ref: ref_field.clone(),
                        repo_id: repo.id.into_inner() as i64,
                        author,
                        message,
                    };

                    // Insert the commit into the database
                    GitHubCommit::create(conn, github_commit.clone()).await?;

                    // Try to fetch devenv.yaml to determine VM configurations
                    let devenv_yaml_content = match installation_client
                        .repos(owner_name.clone(), repo.name.clone())
                        .get_content()
                        .path("devenv.yaml")
                        .r#ref(&ref_field)
                        .send()
                        .await
                    {
                        Ok(content) if !content.items.is_empty() => {
                            if let Some(content) = content.items[0].decoded_content() {
                                Some(content)
                            } else {
                                tracing::warn!("Failed to decode devenv.yaml content");
                                None
                            }
                        }
                        _ => None,
                    };

                    // Parse devenv.yaml and get VM configurations
                    let yaml_str = devenv_yaml_content.as_deref().unwrap_or("");
                    let cloud_config = crate::runner::cloudconfig::FinalCloud::new(yaml_str)
                        .map_err(|e| eyre!("Failed to parse devenv.yaml: {}", e))?;
                    let vms = cloud_config.into_vms();

                    // Create a job for each VM configuration
                    for vm in vms {
                        github_commit.create_job(app_state.clone(), vm).await?;
                    }
                }
            }
            _ => {}
        },
        _ => {}
    }
    Ok(())
}

#[derive(serde::Serialize, utoipa::ToSchema)]
struct RepoJobs {
    owner: String,
    repo: String,
    commits: Vec<Commit>,
}

#[utoipa::path(
    get,
    path = "/{owner}/{repo}/jobs",
    params(
        ("owner" = String, Path, description = "The repository owner"),
        ("repo" = String, Path, description = "The repository name")
    ),
    responses((status = OK, body = RepoJobs))
)]
async fn get_repo_jobs(
    State(app_state): State<AppState>,
    _user: BetaUser,
    axum::extract::Path((owner_login, repo_name)): axum::extract::Path<(String, String)>,
) -> Result<Json<RepoJobs>> {
    let conn = &mut app_state.pool.get().await?;

    // Fetch owner and repo records
    let owner_record = GithubOwner::get_by_login(conn, &owner_login).await?;
    let repo_record = GitHubRepo::get_by_owner_and_name(conn, owner_record.id, &repo_name).await?;

    // Fetch GitHub jobs and regular jobs in one query with a join
    // and create a map from commit ID to a vector of JobResponse
    let mut commit_jobs_map: std::collections::HashMap<uuid::Uuid, Vec<JobResponse>> =
        std::collections::HashMap::new();

    // Use a join to get both JobGitHub and Job in one query
    let job_pairs = JobGitHub::get_jobs_for_repo(conn, repo_record.id).await?;

    // Group jobs by commit ID
    for (github_job, job) in job_pairs {
        commit_jobs_map
            .entry(github_job.commit_id)
            .or_insert_with(Vec::new)
            .push({
                // Generate a log URL for this job
                let log_url = format!("{}/{}", app_state.config.logger_url, job.id);
                let commit = GitHubCommit::get_by_id(conn, github_job.commit_id)
                    .await
                    .unwrap();
                JobResponse {
                    github: github_job,
                    job,
                    commit,
                    log_url,
                }
            });
    }

    // Simply order by id desc - UUIDv7 is time-based so this gives newest first
    let commits = GitHubCommit::get_by_repo_ordered(conn, repo_record.id).await?;

    // Map the commits to the final format with their associated jobs
    // Use remove instead of get+clone to avoid unnecessary copying
    // Also clone owner_login and repo_name once outside the loop
    let owner = owner_login.clone();
    let repo = repo_name.clone();

    let commits = commits
        .into_iter()
        .map(move |commit| {
            let jobs = commit_jobs_map.remove(&commit.id).unwrap_or_default();
            Commit {
                owner: owner.clone(),
                repo: repo.clone(),
                rev: commit.rev,
                r#ref: commit.r#ref,
                author: commit.author,
                message: commit.message,
                jobs,
            }
        })
        .collect();

    Ok(Json(RepoJobs {
        owner: owner_login,
        repo: repo_name,
        commits,
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(get_repos))
        .routes(routes!(get_rev))
        .routes(routes!(get_repo_jobs))
        .routes(routes!(webhook))
}
