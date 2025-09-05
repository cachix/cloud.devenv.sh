variable "zitadel_domain" {
  description = "Zitadel domain (without port or protocol)"
  type        = string
  default     = "localhost"
}

variable "zitadel_port" {
  description = "Zitadel port"
  type        = number
  default     = 9500
}

variable "insecure" {
  description = "Whether to use HTTP instead of HTTPS"
  type        = bool
  default     = true
}

variable "project_name" {
  description = "Zitadel project name"
  type        = string
  default     = "devenv"
}

variable "api_app_name" {
  description = "API application name"
  type        = string
  default     = "devenv-api"
}

variable "oidc_app_name" {
  description = "OIDC application name"
  type        = string
  default     = "devenv-oidc"
}

variable "state_dir" {
  description = "Directory to store state files"
  type        = string
  default     = ".devenv/state/zitadel"
}

variable "redirect_uris" {
  description = "OIDC redirect URIs"
  type        = list(string)
  default     = ["http://localhost:1234/"]
}

variable "post_logout_redirect_uris" {
  description = "OIDC post logout redirect URIs"
  type        = list(string)
  default     = ["http://localhost:1234/"]
}

variable "github_client_id" {
  description = "GitHub OAuth client ID for Identity Provider"
  type        = string
  default     = ""
}

variable "github_client_secret" {
  description = "GitHub OAuth client secret for Identity Provider"
  type        = string
  default     = ""
  sensitive   = true
}

variable "org_name" {
  description = "The name of the organization"
  type        = string
  nullable    = true
  default     = null
}

variable "org_domain" {
  description = "The domain of the organization"
  type        = string
  default     = "localhost"
}

variable "base_url" {
  description = "Base URL of the backend API"
  type        = string
  default     = "http://localhost:8080"
}
