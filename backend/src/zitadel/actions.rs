use crate::config::AppState;
use async_trait::async_trait;
use axum::{Json, body::Bytes, extract::State, http::HeaderMap};
use std::{error::Error as StdError, fmt};
use zitadel::actions::{ActionHandler, ActionRequest, ActionResponse};

#[derive(Debug)]
pub struct ActionError(String);

impl fmt::Display for ActionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Action error: {}", self.0)
    }
}

impl StdError for ActionError {}

impl From<String> for ActionError {
    fn from(s: String) -> Self {
        ActionError(s)
    }
}

impl From<&str> for ActionError {
    fn from(s: &str) -> Self {
        ActionError(s.to_string())
    }
}

pub struct ZitadelActionHandler {
    pub state: AppState,
}

#[async_trait]
impl ActionHandler for ZitadelActionHandler {
    type Error = ActionError;

    async fn complement_token(
        &self,
        req: &ActionRequest,
    ) -> std::result::Result<ActionResponse, Self::Error> {
        tracing::info!("Handling complement_token action");
        tracing::info!("Full ActionRequest data: {:#?}", req);
        tracing::debug!(
            "Request user: {:?}, service_account: {:?}",
            req.user,
            req.service_account
        );

        // Check if user has beta_user role for beta access
        let mut response = ActionResponse::default();

        // For now, just add a default beta_access claim
        // TODO: Figure out how to access user grants in actions-v3 API
        let beta_access = false; // Default to false until we figure out grants access

        response = response.add_claim("beta_access", beta_access.to_string());

        if let Some(user) = &req.user {
            tracing::info!(
                "Set beta_access claim: {} for user {:?}",
                beta_access,
                user.id
            );
        }

        Ok(response)
    }

    async fn pre_userinfo_creation(
        &self,
        req: &ActionRequest,
    ) -> std::result::Result<ActionResponse, Self::Error> {
        tracing::info!("Handling pre_userinfo_creation action for GitHub profile population");
        tracing::info!(
            "Full ActionRequest data for pre_userinfo_creation: {:#?}",
            req
        );

        let mut response = ActionResponse::default();

        // Try to extract GitHub name and set profile fields
        // This is a post-authentication hook where we can modify the user profile
        // We'll set given_name and family_name based on the GitHub profile

        // For now, we'll set default values since we need to figure out how to access
        // the IDP information in the actions-v3 API structure
        tracing::info!("Setting default profile fields for GitHub user");

        // We can't easily access the GitHub data here in pre_userinfo_creation
        // This might need to be handled in a different hook or method

        Ok(response)
    }
}

#[utoipa::path(
    post,
    path = "/webhook",
    responses(
        (status = 200, description = "Action processed successfully"),
        (status = 400, description = "Bad request")
    )
)]
pub async fn webhook_endpoint(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<axum::response::Response, zitadel::actions::WebhookError> {
    tracing::info!("Received webhook request");
    tracing::info!("Headers: {:#?}", headers);
    tracing::info!("Raw body: {}", String::from_utf8_lossy(&body));

    // Get webhook signing key from secretspec
    let webhook_secret = state
        .secrets
        .zitadel_webhook_secret
        .as_ref()
        .ok_or_else(|| zitadel::actions::WebhookError::InvalidSignature)?;

    // Use WebhookVerifier to verify the payload
    use zitadel::actions::WebhookVerifier;

    let signature = headers
        .get("zitadel-signature")
        .and_then(|v| v.to_str().ok())
        .ok_or(zitadel::actions::WebhookError::InvalidSignature)?;

    let verifier = WebhookVerifier::new(webhook_secret);
    verifier
        .verify(&body, signature)
        .map_err(|_| zitadel::actions::WebhookError::InvalidSignature)?;

    // Parse the JSON payload
    let webhook_data: serde_json::Value = serde_json::from_slice(&body)
        .map_err(|e| zitadel::actions::WebhookError::InvalidBody(e.to_string()))?;

    tracing::info!("Parsed webhook data: {:#?}", webhook_data);

    // Check both fullMethod and function fields to determine which handler to run
    let full_method = webhook_data
        .get("fullMethod")
        .and_then(|m| m.as_str())
        .unwrap_or("");

    let function = webhook_data
        .get("function")
        .and_then(|f| f.as_str())
        .unwrap_or("");

    tracing::info!(
        "Handling method: '{}', function: '{}'",
        full_method,
        function
    );

    // Handle function-based triggers first, then method-based triggers
    if !function.is_empty() {
        match function {
            "function/preuserinfo" => {
                let result = handle_preuserinfo(&webhook_data).await?;
                Ok(axum::response::Response::builder()
                    .status(200)
                    .header("content-type", "application/json")
                    .body(axum::body::Body::from(
                        serde_json::to_string(&result).map_err(|e| {
                            zitadel::actions::WebhookError::InvalidBody(e.to_string())
                        })?,
                    ))
                    .unwrap())
            }
            _ => {
                tracing::warn!("Unhandled function: {}", function);
                Ok(axum::response::Response::builder()
                    .status(200)
                    .body(axum::body::Body::empty())
                    .unwrap())
            }
        }
    } else {
        match full_method {
            "/zitadel.user.v2.UserService/RetrieveIdentityProviderIntent" => {
                let result = handle_retrieve_identity_provider_intent(&webhook_data).await?;
                Ok(axum::response::Response::builder()
                    .status(200)
                    .header("content-type", "application/json")
                    .body(axum::body::Body::from(
                        serde_json::to_string(&result.0).map_err(|e| {
                            zitadel::actions::WebhookError::InvalidBody(e.to_string())
                        })?,
                    ))
                    .unwrap())
            }
            _ => {
                tracing::warn!("Unhandled method: {}", full_method);
                Ok(axum::response::Response::builder()
                    .status(200)
                    .body(axum::body::Body::empty())
                    .unwrap())
            }
        }
    }
}

async fn handle_retrieve_identity_provider_intent(
    webhook_data: &serde_json::Value,
) -> Result<Json<serde_json::Value>, zitadel::actions::WebhookError> {
    tracing::info!("Handling RetrieveIdentityProviderIntent");

    // Extract the response field if it exists
    if let Some(mut response) = webhook_data.get("response").cloned() {
        tracing::info!("Processing response field: {:#?}", response);

        // Extract name first to avoid borrowing conflicts
        let name_from_github = response
            .get("idpInformation")
            .and_then(|idp| idp.get("rawInformation"))
            .and_then(|raw| raw.get("name"))
            .and_then(|n| n.as_str())
            .map(|s| s.to_string());

        // Try to set given_name and family_name fields in the user profile
        if let Some(name) = name_from_github {
            if let Some(add_human_user) = response.get_mut("addHumanUser") {
                if let Some(profile) = add_human_user.get_mut("profile") {
                    tracing::info!("Setting given_name: '{}', family_name: '-'", name);

                    if let Some(profile_obj) = profile.as_object_mut() {
                        profile_obj
                            .insert("givenName".to_string(), serde_json::Value::String(name));
                        profile_obj.insert(
                            "familyName".to_string(),
                            serde_json::Value::String("-".to_string()),
                        );
                    }
                }
            }
        }

        tracing::info!("Returning modified response: {:#?}", response);
        return Ok(Json(response));
    }

    // If no response field, return empty JSON object
    tracing::info!("No response field found, returning empty response");
    Ok(Json(serde_json::json!({})))
}

async fn handle_preuserinfo(
    webhook_data: &serde_json::Value,
) -> Result<serde_json::Value, zitadel::actions::WebhookError> {
    tracing::info!("Handling preuserinfo function");
    tracing::info!("Full webhook data for preuserinfo: {:#?}", webhook_data);

    // Check if user has beta_user role in user_grants
    let mut beta_access = false;

    if let Some(user_grants) = webhook_data.get("user_grants").and_then(|g| g.as_array()) {
        tracing::info!("Found user_grants: {:#?}", user_grants);

        for grant in user_grants {
            if let Some(roles) = grant.get("roles").and_then(|r| r.as_array()) {
                tracing::info!("Grant roles: {:#?}", roles);

                for role in roles {
                    if let Some(role_str) = role.as_str() {
                        if role_str == "beta_user" {
                            beta_access = true;
                            tracing::info!("Found beta_user role, setting beta_access to true");
                            break;
                        }
                    }
                }

                if beta_access {
                    break;
                }
            }
        }
    } else {
        tracing::info!("No user_grants found or not an array");
    }

    if let Some(user) = webhook_data.get("user") {
        if let Some(user_id) = user.get("id").and_then(|id| id.as_str()) {
            tracing::info!(
                "Set beta_access claim: {} and metadata for user {}",
                beta_access,
                user_id
            );
        }
    }

    // Create ActionResponse with beta_access claim and metadata
    let response = zitadel::actions::ActionResponse::default()
        .add_claim("beta_access", beta_access.to_string())
        .add_metadata("beta_access_metadata", beta_access.to_string())
        .add_metadata("processed_by", "preuserinfo_handler".to_string());

    // Serialize the ActionResponse to JSON
    let serialized = serde_json::to_value(response)
        .map_err(|e| zitadel::actions::WebhookError::InvalidBody(e.to_string()))?;

    tracing::info!("Returning ActionResponse: {:#?}", serialized);

    Ok(serialized)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_action_error_creation() {
        let error = ActionError::from("Test error");
        assert_eq!(format!("{}", error), "Action error: Test error");
    }

    #[test]
    fn test_action_error_from_string() {
        let error = ActionError::from("Another error".to_string());
        assert!(format!("{}", error).contains("Another error"));
    }
}
