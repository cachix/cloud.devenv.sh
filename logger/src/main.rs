use devenv_logger::{AppState, create_app, create_db};
use std::sync::Arc;
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize SlateDB with filesystem storage
    let logs_path = std::env::var("DEVENV_STATE")
        .map(|state| format!("{}/logs", state))
        .map_err(|_| "DEVENV_STATE environment variable is not set")?;

    let db = create_db(&logs_path).await?;

    let shared_state = Arc::new(AppState { db });
    let app = create_app(shared_state);

    // Start the server
    let port = std::env::var("PORT").unwrap_or_else(|_| "3000".to_string());
    let addr = format!("0.0.0.0:{}", port);
    let listener = TcpListener::bind(&addr).await?;
    println!("Listening on http://{}", listener.local_addr()?);
    axum::serve(listener, app).await?;
    Ok(())
}
