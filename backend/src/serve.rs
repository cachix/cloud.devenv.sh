use crate::config::{AppState, Config, FrontendConfig, SecretSpec};
use axum::Json;
use axum::extract::State;
use eyre::Context;
use eyre::Result;
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
        .nest("/api/v1/zitadel/actions", crate::zitadel::serve::router())
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

    let addr = format!("0.0.0.0:{}", app_state.config.port);
    tracing::info!("Listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    let (router, _) = router().split_for_parts();
    let router = router.with_state(app_state);
    axum::serve(listener, router).await.wrap_err("serve")
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
