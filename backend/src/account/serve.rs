use crate::auth::BetaUser;
use crate::config::AppState;
use crate::error::Result;
use axum::{Json, extract::State};
use utoipa_axum::{router::OpenApiRouter, routes};

use super::model::Account;

#[utoipa::path(
    get,
    path = "/me",
    responses(
        (status = 200, description = "Account found", body = Account),
        (status = 404, description = "Not logged in")
    )
)]
#[tracing::instrument(skip_all, ret)]
pub async fn get_account(
    user: BetaUser,
    State(_state): State<AppState>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("/me for account_id={}", user.account_id);

    // Return user information from local database
    let user_info = serde_json::json!({
        "user_id": user.account_id.to_string(),
        "name": user.name,
        "email": user.email,
        "avatar_url": user.avatar_url,
        "beta_access": true, // This user always has beta access since we validate it
    });

    Ok(Json(user_info))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(get_account))
}
