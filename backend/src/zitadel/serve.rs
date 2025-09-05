use crate::config::AppState;
use utoipa_axum::{router::OpenApiRouter, routes};

use super::actions;

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(actions::webhook_endpoint))
}
