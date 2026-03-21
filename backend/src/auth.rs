//! Authentication extractors for the backend API.
//!
//! This module provides extractors that authenticate requests using session cookies
//! managed by oauth-kit and check role-based access.

use axum::{
    extract::{FromRef, FromRequestParts},
    http::{StatusCode, request::Parts},
    response::{IntoResponse, Response},
};
use diesel::prelude::*;
use diesel_async::RunQueryDsl;
use oauth_kit::axum::AuthUser;
use uuid::Uuid;

use crate::config::{AppState, DbPool};
use crate::schema::{account_role, accounts, oauth_account};

/// A wrapper around the authenticated user that ensures they have the beta_user role.
#[derive(Debug, Clone)]
pub struct BetaUser {
    /// The user's account ID.
    pub account_id: Uuid,
    /// The user's email address (if available).
    pub email: Option<String>,
    /// The user's display name (if available).
    pub name: Option<String>,
    /// The user's avatar URL (if available).
    pub avatar_url: Option<String>,
    /// The user's login/username from the OAuth provider (e.g. GitHub login).
    pub username: Option<String>,
}

/// Custom error for authorization failures.
#[derive(Debug)]
pub struct AuthorizationError {
    pub message: String,
}

impl IntoResponse for AuthorizationError {
    fn into_response(self) -> Response {
        (StatusCode::FORBIDDEN, self.message).into_response()
    }
}

/// Query struct for fetching account details.
#[derive(Queryable, Selectable)]
#[diesel(table_name = crate::schema::accounts)]
struct AccountDetails {
    id: Uuid,
    email: Option<String>,
    name: Option<String>,
    avatar_url: Option<String>,
}

/// Query struct for fetching OAuth profile data.
#[derive(Queryable, Selectable)]
#[diesel(table_name = crate::schema::oauth_account)]
struct OAuthProfile {
    raw_profile: Option<serde_json::Value>,
}

impl<S> FromRequestParts<S> for BetaUser
where
    S: Send + Sync,
    DbPool: FromRef<S>,
{
    type Rejection = AuthorizationError;

    fn from_request_parts(
        parts: &mut Parts,
        state: &S,
    ) -> impl std::future::Future<Output = Result<Self, Self::Rejection>> + Send {
        async move {
            // Extract the authenticated user ID from the session
            let auth_user: AuthUser<Uuid> = AuthUser::from_request_parts(parts, state)
                .await
                .map_err(|_| AuthorizationError {
                    message: "Authentication required".to_string(),
                })?;

            let account_id = auth_user.0;
            let pool = DbPool::from_ref(state);

            // Get a database connection
            let mut conn = pool.get().await.map_err(|e| {
                tracing::error!("Failed to get database connection: {}", e);
                AuthorizationError {
                    message: "Internal server error".to_string(),
                }
            })?;

            // Fetch account details with beta_user role check and OAuth profile in a single query
            let result: Option<(AccountDetails, OAuthProfile)> = accounts::table
                .inner_join(account_role::table)
                .inner_join(oauth_account::table)
                .filter(accounts::id.eq(account_id))
                .filter(account_role::role.eq("beta_user"))
                .select((AccountDetails::as_select(), OAuthProfile::as_select()))
                .first(&mut conn)
                .await
                .optional()
                .map_err(|e| {
                    tracing::error!("Failed to fetch account with beta role: {}", e);
                    AuthorizationError {
                        message: "Internal server error".to_string(),
                    }
                })?;

            let (account, oauth_profile) = result.ok_or_else(|| {
                tracing::debug!("User {} does not have beta_user role", account_id);
                AuthorizationError {
                    message: "Beta access required. Please contact support to get beta access."
                        .to_string(),
                }
            })?;

            // Extract username/login from the OAuth provider's raw profile
            let username = oauth_profile
                .raw_profile
                .as_ref()
                .and_then(|p| p.get("login"))
                .and_then(|v| v.as_str())
                .map(String::from);

            tracing::debug!("User {} has beta access", account_id);

            Ok(BetaUser {
                account_id: account.id,
                email: account.email,
                name: account.name,
                avatar_url: account.avatar_url,
                username,
            })
        }
    }
}

impl FromRef<AppState> for DbPool {
    fn from_ref(state: &AppState) -> Self {
        state.pool.clone()
    }
}
