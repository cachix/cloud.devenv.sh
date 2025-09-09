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

provider "zitadel" {
  domain           = var.zitadel_domain
  insecure         = var.insecure
  port             = var.zitadel_port
  jwt_profile_file = "${var.state_dir}/devenv-cli.token"
}

module "zitadel" {
  source = "./module"

  config = {
    zitadel_domain            = var.zitadel_domain
    zitadel_port              = var.zitadel_port
    insecure                  = var.insecure
    project_name              = var.project_name
    api_app_name              = var.api_app_name
    oidc_app_name             = var.oidc_app_name
    state_dir                 = var.state_dir
    redirect_uris             = var.redirect_uris
    post_logout_redirect_uris = var.post_logout_redirect_uris
    github_client_id          = var.github_client_id
    github_client_secret      = var.github_client_secret
    org_name                  = var.org_name
    org_domain                = var.org_domain
    base_url                  = var.base_url
  }
}

# Outputs from the module
output "project_id" {
  description = "The Zitadel project ID"
  value       = module.zitadel.project_id
}

output "api_app_id" {
  description = "The API application ID"
  value       = module.zitadel.api_app_id
}

output "oidc_client_id" {
  description = "The OIDC application client ID"
  value       = module.zitadel.oidc_client_id
}