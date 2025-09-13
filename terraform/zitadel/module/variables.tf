variable "config" {
  description = "Configuration object for Zitadel module"
  type = object({
    zitadel_domain            = string
    zitadel_port              = number
    insecure                  = bool
    project_name              = string
    api_app_name              = string
    oidc_app_name             = string
    state_dir                 = string
    redirect_uris             = list(string)
    post_logout_redirect_uris = list(string)
    github_client_id          = string
    github_client_secret      = string
    org_name                  = string
    org_domain                = string
    base_url                  = string
  })
}