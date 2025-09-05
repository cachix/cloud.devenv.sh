# Zitadel Terraform Configuration

This Terraform configuration bootstraps a local Zitadel instance with the necessary project, applications, and identity providers using the official Zitadel Terraform provider.

## Prerequisites

1. Zitadel instance running locally (ensure `devenv up` is running)
2. Access token available at `.devenv/state/zitadel/devenv-cli.token`
3. Environment variables set in `.env` file (see main README):
   - `BASE_URL`
   - `TF_VAR_github_client_id`
   - `TF_VAR_github_client_secret`
   - `TF_VAR_redirect_uris=[ "http://localhost:1234/", "<BASE_URL>/" ]`

## Usage

1. Navigate to the terraform directory:

   ```bash
   cd terraform/zitadel
   ```

2. If you need to reset state (e.g., after destroying Zitadel):

   ```bash
   rm -f terraform.tfstate terraform.tfstate.backup
   ```

3. Initialize Terraform:

   ```bash
   terraform init
   ```

4. Source environment variables and apply the configuration:

   ```bash
   source ../../.env
   terraform apply -auto-approve
   ```

5. After successful application, save the OIDC client ID to `.env`:

   ```bash
   # The output will show: oidc_client_id = "324975956655805494"
   # Add or update in .env:
   export OAUTH_AUDIENCE=http://localhost:9500
   export OAUTH_CLIENT_ID=<oidc_client_id_from_output>
   ```

6. Reload your shell to pick up the new environment variables:
   ```bash
   source .env
   ```

## Configuration

| Variable                    | Description                               | Default                      |
| --------------------------- | ----------------------------------------- | ---------------------------- |
| `zitadel_domain`            | Zitadel domain (without port or protocol) | `localhost`                  |
| `zitadel_port`              | Zitadel port                              | `9500`                       |
| `insecure`                  | Whether to use HTTP instead of HTTPS      | `true`                       |
| `project_name`              | Zitadel project name                      | `devenv`                     |
| `api_app_name`              | API application name                      | `devenv-api`                 |
| `oidc_app_name`             | OIDC application name                     | `devenv-oidc`                |
| `state_dir`                 | Directory to store state files            | `.devenv/state/zitadel`      |
| `redirect_uris`             | OIDC redirect URIs                        | `["http://localhost:1234/"]` |
| `post_logout_redirect_uris` | OIDC post logout redirect URIs            | `["http://localhost:1234/"]` |
| `github_client_id`          | GitHub OAuth client ID for IdP            | `""`                         |
| `github_client_secret`      | GitHub OAuth client secret for IdP        | `""`                         |
| `create_org`                | Whether to create a new organization      | `false`                      |
| `existing_org_id`           | ID of an existing organization to use     | `"default"`                  |

## Resources Created

1. Zitadel Organization (optional)
2. Zitadel Project
3. API Application with JWT authentication
4. OIDC Application for user authentication
5. Personal Access Token for the API application
6. GitHub Identity Provider (optional)
7. Domain and Login Policies for GitHub authentication (when GitHub IdP is enabled)

## Outputs

| Output           | Description                    |
| ---------------- | ------------------------------ |
| `project_id`     | The Zitadel project ID         |
| `api_app_id`     | The API application ID         |
| `oidc_client_id` | The OIDC application client ID |

## Notes

- This configuration requires the Zitadel instance to be already running
- The `.devenv/state/zitadel/devenv-cli.token` file must exist and contain a valid access token
- By default, resources are created in the default organization. Use `create_org = true` to create a new organization.
- GitHub IdP is created only if both client ID and secret are provided
- For more details on the Zitadel provider, see the [official documentation](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs)
