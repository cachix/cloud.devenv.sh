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
    tracing::info!("/me");
    tracing::info!("{:?}", user);

    // Return user information from Zitadel introspection
    let user_info = serde_json::json!({
        "user_id": user.sub,
        "username": user.username,
        "name": user.name,
        "given_name": user.given_name,
        "family_name": user.family_name,
        "preferred_username": user.preferred_username,
        "email": user.email,
        "email_verified": user.email_verified,
        "locale": user.locale,
        "beta_access": true, // This user always has beta access since we validate it
    });

    Ok(Json(user_info))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(get_account))
}
