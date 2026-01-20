use std::ops::Deref;
use std::path::Path;
use std::sync::Arc;

use diesel_async::AsyncPgConnection;
use diesel_async::async_connection_wrapper::AsyncConnectionWrapper;
use diesel_async::pooled_connection::AsyncDieselConnectionManager;
use diesel_async::pooled_connection::deadpool::Object;
use diesel_async::pooled_connection::deadpool::Pool;
use diesel_migrations::{EmbeddedMigrations, MigrationHarness, embed_migrations};
use eyre::Result;
use octocrab::Octocrab;
use serde::{Deserialize, Serialize};
use url::Url;

use crate::oauth_store::PostgresUserStore;

secretspec_derive::declare_secrets!("../secretspec.toml");

/// Database connection pool type alias.
pub type DbPool = Pool<AsyncPgConnection>;

fn default_port() -> u16 {
    8080
}

#[derive(Deserialize)]
pub struct Config {
    pub base_url: Url,
    #[serde(default = "default_port")]
    pub port: u16,
    pub github: GitHub,
    #[serde(default)]
    pub job: Job,
    #[serde(default = "default_logger_url")]
    pub logger_url: String,
}

fn default_logger_url() -> String {
    "http://localhost:3000".to_string()
}

#[derive(Serialize, Deserialize, utoipa::ToSchema)]
pub struct FrontendConfig {
    pub github_app_name: String,
}

impl Config {
    pub fn new(config_path: &Path) -> Result<Self> {
        if !config_path.exists() {
            return Err(eyre::eyre!(
                "Config file not found: {}",
                config_path.display()
            ));
        }
        let config_str = std::fs::read_to_string(config_path)?;
        let config: Config = toml::from_str(&config_str)?;
        Ok(config)
    }
}

#[derive(Deserialize)]
pub struct GitHub {
    pub app_id: u64,
    pub app_name: String,
}

fn default_job_timeout_seconds() -> u64 {
    3600 // Default to 1 hour (3600 seconds)
}

#[derive(Deserialize)]
pub struct Job {
    #[serde(default = "default_job_timeout_seconds")]
    pub timeout_seconds: u64,
}

impl Default for Job {
    fn default() -> Self {
        Self {
            timeout_seconds: default_job_timeout_seconds(),
        }
    }
}

#[derive(Clone)]
pub struct AppState(Arc<InnerState>);

impl Deref for AppState {
    type Target = InnerState;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

pub struct InnerState {
    pub config: Config,
    pub secrets: SecretSpec,
    pub pool: Pool<AsyncPgConnection>,
    pub oauth_store: PostgresUserStore,
    pub github: Octocrab,
    pub posthog: Option<posthog_rs::Client>,
    pub runner_state: crate::runner::serve::RunnerState,
}

pub const MIGRATIONS: EmbeddedMigrations = embed_migrations!();

impl AppState {
    pub async fn new(config: Config, secrets: SecretSpec) -> Result<Self, eyre::Error> {
        let database_url = match &secrets.database_url {
            Some(secret) => secret.clone(),
            None => {
                // Fallback to PGHOST for Unix socket connection
                match std::env::var("PGHOST") {
                    Ok(host) => format!("postgres:///devenv?host={}", host),
                    Err(_) => return Err(eyre::eyre!("Neither DATABASE_URL nor PGHOST is set")),
                }
            }
        };

        let manager =
            AsyncDieselConnectionManager::<diesel_async::AsyncPgConnection>::new(&database_url);
        let pool = Pool::builder(manager)
            .build()
            .map_err(|e| eyre::eyre!("Failed to create database pool: {}", e))?;

        // Create OAuth user store
        let oauth_store = PostgresUserStore::new(pool.clone());

        let app_private_key = jsonwebtoken::EncodingKey::from_rsa_pem(
            secrets
                .github_app_private_key
                .as_ref()
                .ok_or_else(|| eyre::eyre!("GitHub App private key not configured"))?
                .as_bytes(),
        )
        .map_err(|e| eyre::eyre!("Failed to parse Github private key: {}", e))?;

        // Now create the authenticated app client with the fetched ID
        let github = Octocrab::builder()
            .app(
                octocrab::models::AppId(config.github.app_id),
                app_private_key,
            )
            .build()?;
        // For posthog-rs 0.3+, client() returns a Future that needs to be awaited
        let posthog = if let Some(key) = &secrets.posthog_api_key {
            Some(posthog_rs::client(key.as_str()).await)
        } else {
            None
        };

        // Create the RunnerState
        let runner_state = crate::runner::serve::RunnerState::new();

        let state = InnerState {
            config,
            secrets,
            pool,
            oauth_store,
            github,
            posthog,
            runner_state,
        };

        Ok(Self(Arc::new(state)))
    }

    pub async fn run_migrations(self: &AppState) -> Result<()> {
        tracing::info!("Running database migrations");
        let conn = self.pool.get().await?;
        let mut async_wrapper: AsyncConnectionWrapper<Object<AsyncPgConnection>> =
            AsyncConnectionWrapper::from(conn);
        tokio::task::spawn_blocking(move || {
            async_wrapper.run_pending_migrations(MIGRATIONS).unwrap();
        })
        .await?;
        Ok(())
    }
}
