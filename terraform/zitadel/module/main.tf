terraform {
  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 2.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
  required_version = ">= 1.0.0"
}

data "local_file" "access_token" {
  filename = local.access_token_file
}

data "zitadel_orgs" "default" {
  name          = var.config.org_name
  name_method   = "TEXT_QUERY_METHOD_EQUALS_IGNORE_CASE"
  domain        = var.config.org_domain
  domain_method = "TEXT_QUERY_METHOD_EQUALS_IGNORE_CASE"
  state         = "ORG_STATE_ACTIVE"
}

locals {
  access_token_file = "${var.config.state_dir}/devenv-cli.token"
  app_key_path      = "${var.config.state_dir}/devenv-app-key.json"
}

data "zitadel_org" "project_org" {
  id = data.zitadel_orgs.default.ids[0]
}

# Create the project
resource "zitadel_project" "project" {
  name   = var.config.project_name
  org_id = data.zitadel_org.project_org.id
  project_role_assertion  = true
}

# Create beta_user role for beta access control
resource "zitadel_project_role" "beta_user" {
  org_id     = data.zitadel_org.project_org.id
  project_id = zitadel_project.project.id
  role_key   = "beta_user"
  display_name = "Beta User"
  group        = "access_control"
}

# Create the API application
resource "zitadel_application_api" "api_app" {
  project_id       = zitadel_project.project.id
  org_id           = data.zitadel_org.project_org.id
  name             = var.config.api_app_name
  auth_method_type = "API_AUTH_METHOD_TYPE_PRIVATE_KEY_JWT"
}

data "zitadel_machine_users" "default" {
  org_id           = data.zitadel_org.project_org.id
  user_name        = "devenv-cli"
  user_name_method = "TEXT_QUERY_METHOD_EQUALS_IGNORE_CASE"
}

data "zitadel_machine_user" "devenv_cli" {
  org_id  = data.zitadel_org.project_org.id
  user_id = data.zitadel_machine_users.default.user_ids[0]
}

# Create an API key for the application
resource "zitadel_application_key" "api_key" {
  org_id          = data.zitadel_org.project_org.id
  project_id      = zitadel_project.project.id
  app_id          = zitadel_application_api.api_app.id
  key_type        = "KEY_TYPE_JSON"
  expiration_date = "2519-04-01T08:45:00Z"
}

# Save the API key to file
resource "local_file" "api_key_file" {
  content  = zitadel_application_key.api_key.key_details
  filename = local.app_key_path
}

# Create the OIDC application
resource "zitadel_application_oidc" "oidc_app" {
  project_id                  = zitadel_project.project.id
  org_id                      = data.zitadel_org.project_org.id
  name                        = var.config.oidc_app_name
  redirect_uris               = var.config.redirect_uris
  response_types              = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                 = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type                    = "OIDC_APP_TYPE_USER_AGENT"
  auth_method_type            = "OIDC_AUTH_METHOD_TYPE_NONE"
  post_logout_redirect_uris   = var.config.post_logout_redirect_uris
  dev_mode                    = true
  access_token_type           = "OIDC_TOKEN_TYPE_BEARER"
  access_token_role_assertion = false
  id_token_role_assertion     = false
  id_token_userinfo_assertion = true
  clock_skew                  = "0s"
}

# Create the GitHub Identity Provider (if credentials are provided)
resource "zitadel_org_idp_github" "github" {
  count         = var.config.github_client_id != "" && var.config.github_client_secret != "" ? 1 : 0
  org_id        = data.zitadel_org.project_org.id
  name          = "GitHub"
  client_id     = var.config.github_client_id
  client_secret = var.config.github_client_secret
  # https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps
  scopes              = ["openid", "email"]
  auto_linking        = "AUTO_LINKING_OPTION_EMAIL"
  is_linking_allowed  = true
  is_creation_allowed = true
  is_auto_creation    = true
  is_auto_update      = true
}


# Set up domain policy to allow auth from the IdP
resource "zitadel_domain_policy" "policy" {
  count                                       = var.config.github_client_id != "" && var.config.github_client_secret != "" ? 1 : 0
  org_id                                      = data.zitadel_org.project_org.id
  user_login_must_be_domain                   = false
  validate_org_domains                        = false
  smtp_sender_address_matches_instance_domain = false
}

# Enable IdP for login
resource "zitadel_login_policy" "github_login_policy" {
  count                         = var.config.github_client_id != "" && var.config.github_client_secret != "" ? 1 : 0
  org_id                        = data.zitadel_org.project_org.id
  user_login                    = true
  allow_register                = true
  default_redirect_uri          = var.config.redirect_uris[0]
  allow_external_idp            = true
  idps                          = [zitadel_org_idp_github.github[0].id]
  passwordless_type             = "PASSWORDLESS_TYPE_ALLOWED" # TODO: what is this
  force_mfa                     = false
  force_mfa_local_only          = false
  password_check_lifetime       = "240h0m0s"
  external_login_check_lifetime = "240h0m0s"
  multi_factor_check_lifetime   = "24h0m0s"
  mfa_init_skip_lifetime        = "720h0m0s"
  second_factor_check_lifetime  = "24h0m0s"
  hide_password_reset           = false
  ignore_unknown_usernames      = true
  allow_domain_discovery        = false
  disable_login_with_phone      = true
}

# Create service user for login UI
resource "zitadel_machine_user" "login_client" {
  org_id      = data.zitadel_org.project_org.id
  user_name   = "login-client"
  name        = "Login Client Service User"
  description = "Service user for Zitadel login UI"
  access_token_type = "ACCESS_TOKEN_TYPE_BEARER"
}

# Create PAT for the login client service user
resource "zitadel_personal_access_token" "login_client_pat" {
  org_id          = data.zitadel_org.project_org.id
  user_id         = zitadel_machine_user.login_client.id
  expiration_date = "2519-04-01T08:45:00Z"
}

# Assign IAM_LOGIN_CLIENT role to the login client machine user
resource "zitadel_instance_member" "login_client_role" {
  user_id = zitadel_machine_user.login_client.id
  roles   = ["IAM_LOGIN_CLIENT"]
}

# Save the PAT to file
resource "local_file" "login_client_pat_file" {
  content  = zitadel_personal_access_token.login_client_pat.token
  filename = "${var.config.state_dir}/login-client.pat"
}

# Create service user for Actions v2 management
resource "zitadel_machine_user" "actions_admin" {
  org_id            = data.zitadel_org.project_org.id
  user_name         = "actions-admin"
  name              = "Actions v2 Admin Service User"
  description       = "Service user for managing Actions v2 targets and executions"
  access_token_type = "ACCESS_TOKEN_TYPE_BEARER"
}

# Create PAT for the actions admin service user
resource "zitadel_personal_access_token" "actions_admin_pat" {
  org_id          = data.zitadel_org.project_org.id
  user_id         = zitadel_machine_user.actions_admin.id
  expiration_date = "2519-04-01T08:45:00Z"
}

# Assign IAM_OWNER role to the actions admin machine user
resource "zitadel_instance_member" "actions_admin_role" {
  user_id = zitadel_machine_user.actions_admin.id
  roles   = ["IAM_OWNER"]
}

# Save the actions admin PAT to file
resource "local_file" "actions_admin_pat_file" {
  content  = zitadel_personal_access_token.actions_admin_pat.token
  filename = "${var.config.state_dir}/actions-admin.pat"
}

