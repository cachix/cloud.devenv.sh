use serde::{Deserialize, Serialize};
use slatedb::{
    Db, DbBuilder,
    config::Settings,
    object_store::{ObjectStore, local::LocalFileSystem},
};
use std::sync::Arc;

pub mod server;
pub mod stream;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Log {
    pub message: String,
    pub timestamp: String,
    pub level: String,
}

pub use server::{AppState, create_app};

pub async fn create_db(base_path: &str) -> Result<Arc<Db>, Box<dyn std::error::Error>> {
    std::fs::create_dir_all(base_path)?;
    let object_store: Arc<dyn ObjectStore> = Arc::new(LocalFileSystem::new_with_prefix(base_path)?);

    let settings = Settings::default();
    let db_path = format!("{}/kv_store", base_path);

    Ok(Arc::new(
        DbBuilder::new(db_path, object_store)
            .with_settings(settings)
            .build()
            .await?,
    ))
}
