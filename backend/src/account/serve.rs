use crate::auth::BetaUser;
use crate::config::AppState;
use crate::error::Result;
use axum::Json;
use utoipa_axum::{router::OpenApiRouter, routes};

use super::model::AccountResponse;

#[utoipa::path(
    get,
    path = "/me",
    responses(
        (status = 200, description = "Account found", body = AccountResponse),
        (status = 404, description = "Not logged in")
    )
)]
#[tracing::instrument(skip_all, ret)]
pub async fn get_account(user: BetaUser) -> Result<Json<AccountResponse>> {
    tracing::info!("/me for account_id={}", user.account_id);

    Ok(Json(AccountResponse {
        user_id: user.account_id.to_string(),
        username: user.username,
        name: user.name,
        email: user.email,
        avatar_url: user.avatar_url,
        beta_access: true,
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(get_account))
}
