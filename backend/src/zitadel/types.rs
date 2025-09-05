use serde::{Deserialize, Serialize};

#[derive(Deserialize, Serialize, Debug)]
pub struct ActionRequest<T> {
    #[serde(rename = "fullMethod")]
    pub full_method: String,
    #[serde(rename = "instanceID")]
    pub instance_id: String,
    #[serde(rename = "orgID")]
    pub org_id: String,
    #[serde(rename = "projectID")]
    pub project_id: Option<String>,
    #[serde(rename = "userID")]
    pub user_id: Option<String>,
    pub request: T,
}

#[derive(Deserialize, Serialize, Debug)]
pub struct ActionRequestWithResponse<T, R> {
    #[serde(rename = "fullMethod")]
    pub full_method: String,
    #[serde(rename = "instanceID")]
    pub instance_id: String,
    #[serde(rename = "orgID")]
    pub org_id: String,
    #[serde(rename = "projectID")]
    pub project_id: Option<String>,
    #[serde(rename = "userID")]
    pub user_id: Option<String>,
    pub request: T,
    pub response: R,
}

// Post-authentication request for RetrieveIdentityProviderIntent method
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct PostAuthRequest {
    pub idp_intent_id: String,
    pub idp_intent_token: String,
}

// Response for post-authentication hook (RetrieveIdentityProviderIntent)
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct PostAuthResponse {
    pub idp_information: Option<IdpInformation>,
    pub add_human_user: Option<AddHumanUserInfo>,
}

// Full response from Zitadel webhook that includes the details and response data
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct RetrieveIdpIntentResponse {
    pub details: Option<ResponseDetails>,
    pub idp_information: Option<IdpInformation>,
    pub add_human_user: Option<AddHumanUserInfo>,
    pub user_id: Option<String>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ResponseDetails {
    pub sequence: String,
    pub change_date: String,
    pub resource_owner: String,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct IdpInformation {
    pub idp_id: String,
    pub user_id: String,
    pub user_name: String,
    pub raw_information: Option<serde_json::Value>,
    pub oauth_access_token: Option<String>,
    pub idp_access_token: Option<String>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct AddHumanUserInfo {
    pub username: Option<String>,
    pub profile: Option<Profile>,
    pub email: Option<EmailInfo>,
    pub metadata: Option<Vec<UserMetadata>>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Organization {
    pub org_id: String,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Profile {
    pub given_name: Option<String>,
    pub family_name: Option<String>,
    pub nick_name: Option<String>,
    pub display_name: Option<String>,
    pub preferred_language: Option<String>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct EmailInfo {
    pub email: String,
    pub is_verified: bool,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct IdpLink {
    pub idp_id: String,
    pub user_id: String,
    pub user_name: String,
}

// Token customization request for CreateSession method
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct TokenCustomizationRequest {
    pub user_id: String,
    pub username: String,
    pub user_grants: Option<UserGrants>,
    pub session: Option<SessionInfo>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct UserGrants {
    pub count: u32,
    pub grants: Vec<Grant>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Grant {
    pub project_id: String,
    pub roles: Vec<String>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SessionInfo {
    pub session_id: String,
    pub creation_date: String,
}

#[derive(Deserialize, Serialize, Debug)]
#[serde(rename_all = "snake_case")]
pub struct TokenCustomizationResponse {
    pub append_claims: Option<Vec<Claim>>,
    pub append_log_claims: Option<Vec<String>>,
}

// Common types
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct UserMetadata {
    pub key: String,
    pub value: String, // base64 encoded value
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct SetMetadataEntry {
    pub key: String,
    pub value: Vec<u8>, // raw bytes like in the Go example
}

#[derive(Deserialize, Serialize, Debug)]
pub struct Claim {
    pub key: String,
    pub value: String,
}

// GitHub API types
#[derive(Deserialize, Debug)]
pub struct GitHubEmail {
    pub email: String,
    pub verified: bool,
    pub primary: bool,
}
