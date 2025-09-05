use axum::{
    extract::{FromRef, FromRequestParts},
    http::{StatusCode, request::Parts},
    response::{IntoResponse, Response},
};
use zitadel::axum::introspection::IntrospectedUser;

/// A wrapper around IntrospectedUser that ensures the user has beta_user role
#[derive(Debug)]
pub struct BetaUser(pub IntrospectedUser);

impl std::ops::Deref for BetaUser {
    type Target = IntrospectedUser;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

/// Custom error for authorization failures
#[derive(Debug)]
pub struct AuthorizationError {
    pub message: String,
}

impl IntoResponse for AuthorizationError {
    fn into_response(self) -> Response {
        (StatusCode::FORBIDDEN, self.message).into_response()
    }
}

/// Trait for checking beta access on users
pub trait BetaAccessChecker {
    fn has_beta_access(&self) -> bool;
}

impl BetaAccessChecker for IntrospectedUser {
    fn has_beta_access(&self) -> bool {
        tracing::debug!("Checking beta access for user: {}", self.sub);

        // Check if user has beta_user role in project_roles
        if let Some(_) = self.project_roles.get("beta_user") {
            tracing::debug!("User {} has beta_user in project_roles", self.sub);
            return true;
        }

        // Check if user has beta_user role in org_roles
        if let Some(_) = self.org_roles.get("beta_user") {
            tracing::debug!("User {} has beta_user in org_roles", self.sub);
            return true;
        }

        // Check for beta_user role in custom_claims using the Zitadel OIDC format
        for (claim_name, claim_value) in &self.custom_claims {
            if claim_name.starts_with("urn:zitadel:iam:org:project:")
                && claim_name.ends_with(":roles")
            {
                // Check if claim_value contains beta_user key
                if let Some(roles_obj) = claim_value.as_object() {
                    if roles_obj.contains_key("beta_user") {
                        tracing::debug!(
                            "User {} has beta_user in custom claim: {}",
                            self.sub,
                            claim_name
                        );
                        return true;
                    }
                }
            }
        }

        // Check for direct beta_access claim
        if let Some(beta_access_value) = self.custom_claims.get("beta_access") {
            if let Some(beta_access_bool) = beta_access_value.as_bool() {
                if beta_access_bool {
                    tracing::debug!("User {} has beta_access claim: true", self.sub);
                    return true;
                }
            }
            if let Some(beta_access_str) = beta_access_value.as_str() {
                if beta_access_str.to_lowercase() == "true" {
                    tracing::debug!("User {} has beta_access claim: 'true'", self.sub);
                    return true;
                }
            }
        }

        // Check metadata for beta_access field from webhook actions
        if let Some(beta_access) = self.metadata.get("beta_access") {
            if beta_access.to_lowercase() == "true" {
                tracing::debug!("User {} has beta_access in metadata", self.sub);
                return true;
            }
        }

        tracing::debug!("User {} does not have beta access", self.sub);
        false
    }
}

impl<S> FromRequestParts<S> for BetaUser
where
    S: Send + Sync,
    zitadel::axum::introspection::IntrospectionState: FromRef<S>,
{
    type Rejection = AuthorizationError;

    fn from_request_parts(
        parts: &mut Parts,
        state: &S,
    ) -> impl std::future::Future<Output = Result<Self, Self::Rejection>> + Send {
        async move {
            // First, extract the regular IntrospectedUser
            let user = IntrospectedUser::from_request_parts(parts, state)
                .await
                .map_err(|_| AuthorizationError {
                    message: "Authentication required".to_string(),
                })?;

            // Check if user has beta access
            if user.has_beta_access() {
                Ok(BetaUser(user))
            } else {
                Err(AuthorizationError {
                    message: "Beta access required. Please contact support to get beta access."
                        .to_string(),
                })
            }
        }
    }
}
