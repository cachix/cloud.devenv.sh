output "project_id" {
  description = "The Zitadel project ID"
  value       = zitadel_project.project.id
}

output "api_app_id" {
  description = "The API application ID"
  value       = zitadel_application_api.api_app.id
}

output "oidc_client_id" {
  description = "The OIDC application client ID"
  value       = nonsensitive(zitadel_application_oidc.oidc_app.client_id)
}