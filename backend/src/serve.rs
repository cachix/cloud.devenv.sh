use crate::config::{AppState, Config, FrontendConfig, SecretSpec};
use axum::Json;
use axum::Router;
use axum::extract::State;
use eyre::Context;
use eyre::Result;
use oauth_kit::axum::AuthRouter;
use oauth_kit::provider::providers;
use tower_sessions_cookie_store::{CookieSessionConfig, CookieSessionManagerLayer, Key};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;

#[utoipa::path(get, path = "/metrics", responses((status = OK, body = String)))]
async fn metrics() -> crate::error::Result<String> {
    let metrics = prometheus::default_registry().gather();
    let report = prometheus::TextEncoder::new().encode_to_string(&metrics)?;
    Ok(report)
}

#[utoipa::path(
    get,
    path = "/api/v1/config/",
    responses(
        (status = 200, body = FrontendConfig)
    )
)]
async fn get_config(State(state): State<AppState>) -> crate::error::Result<Json<FrontendConfig>> {
    let config = FrontendConfig {
        github_app_name: state.config.github.app_name.clone(),
    };

    Ok(Json(config))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .nest("/api/v1/github", crate::github::serve::router())
        .nest("/api/v1/account", crate::account::serve::router())
        .nest("/api/v1/job", crate::job::serve::router())
        .nest("/api/v1/runner", crate::runner::serve::router())
        .routes(routes!(metrics))
        .routes(routes!(get_config))
        .layer(
            tower::ServiceBuilder::new()
                .layer(tower_http::trace::TraceLayer::new_for_http())
                .layer(tower_http::catch_panic::CatchPanicLayer::new())
                .layer(sentry_tower::NewSentryLayer::new_from_top())
                .layer(sentry_tower::SentryHttpLayer::with_transaction()),
        )
}

async fn serve(app_state: AppState) -> Result<()> {
    // Start the job timeout checker
    crate::runner::serve::start_job_timeout_checker(app_state.clone());

    // Get OAuth credentials from environment
    let github_client_id = app_state
        .secrets
        .github_oauth_client_id
        .as_ref()
        .ok_or_else(|| eyre::eyre!("GITHUB_OAUTH_CLIENT_ID not configured"))?
        .clone();
    let github_client_secret = app_state
        .secrets
        .github_oauth_client_secret
        .as_ref()
        .ok_or_else(|| eyre::eyre!("GITHUB_OAUTH_CLIENT_SECRET not configured"))?
        .clone();

    // Configure session cookie store
    let session_secret = app_state
        .secrets
        .session_secret
        .as_ref()
        .ok_or_else(|| eyre::eyre!("SESSION_SECRET not configured"))?;
    let secret_bytes = hex::decode(session_secret)
        .map_err(|e| eyre::eyre!("SESSION_SECRET must be valid hex: {}", e))?;
    let key = Key::try_from(secret_bytes.as_slice())
        .map_err(|e| eyre::eyre!("SESSION_SECRET must be 64 bytes: {}", e))?;

    let is_production = app_state.config.base_url.scheme() == "https";
    let cookie_config = CookieSessionConfig::default()
        .with_secure(is_production)
        .with_http_only(true)
        .with_name("devenv_session");
    let session_layer = CookieSessionManagerLayer::private(key).with_config(cookie_config);

    // Create GitHub OAuth provider
    let github = providers::github(&github_client_id, &github_client_secret);
    let base_url = app_state
        .config
        .base_url
        .to_string()
        .trim_end_matches('/')
        .to_string();

    // Build OAuth router
    let auth_router = AuthRouter::new(app_state.oauth_store.clone(), &base_url)
        .with_provider(github)
        .with_signin_redirect("/")
        .with_signout_redirect("/")
        .build();

    let addr = format!("0.0.0.0:{}", app_state.config.port);
    tracing::info!("Listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();

    // Build the API router
    let (api_router, _) = router().split_for_parts();
    let api_router = api_router.with_state(app_state);

    // Combine auth router with API router and apply session layer
    let app = Router::new()
        .merge(auth_router)
        .merge(api_router)
        .layer(session_layer);

    axum::serve(listener, app).await.wrap_err("serve")
}

pub fn main(config: Config) -> Result<()> {
    // Load secrets first (before runtime creation)
    let resolved_secrets = SecretSpec::builder()
        .load()
        .map_err(|e| eyre::eyre!("Failed to load secrets: {}", e))?;
    let secrets = resolved_secrets.secrets;

    // Initialize Sentry early with loaded secrets
    let _sentry = secrets.sentry_dsn.as_ref().map(|dsn| {
        sentry::init((
            dsn.to_string(),
            sentry::ClientOptions {
                release: sentry::release_name!(),
                traces_sample_rate: 1.0,
                ..Default::default()
            },
        ))
    });

    let _recorder = metrics_prometheus::install();

    // Create runtime and run everything in one block_on
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let app_state = AppState::new(config, secrets).await?;
            serve(app_state).await
        })
}
