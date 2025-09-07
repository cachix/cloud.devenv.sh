# cloud.devenv.sh

A cloud-hosted platform that provides GitHub Actions experience using Nix and [devenv](https://devenv.sh).

See talk [What if GitHub Actions were local-first and built using Nix?](https://talks.nixcon.org/nixcon-2025/talk/S8SKEG/).

## Status

Currently in development, sign up for [private beta](https://cloud.devenv.sh).

## Example

On top of regular [devenv.sh](https://devenv.sh) each CI jobs gets extra information:

```nix
{ pkgs, lib, config, ... }:
let
  # https://devenv.sh/cloud/
  github = config.cloud.ci.github;
in {
  # https://devenv.sh/basics/
  packages = [ pkgs.cargo-watch ];

  # https://devenv.sh/languages/
  languages = {
    rust.enable = true;
    python = {
      enable = true;
      venv.enable = true;
      uv.enable = true;
    };
  };

  # https://devenv.sh/processes/
  processes = {
    myapp.exec = "cargo run -x";
  };

  # https://devenv.sh/services/
  services = {
    # run postgresql only locally
    postgresql.enable = !config.cloud.enable;
  };

  # https://devenv.sh/git-hooks/
  git-hooks = {
    hooks.rustfmt.enable = true;
    # run pre-commit hooks only on changes
    fromRef = github.base_ref or null;
    toRef = github.ref or null;
  };

  # https://devenv.sh/tasks/
  tasks = {
    "myapp:tests" = {
      after = [ "devenv:enterTest" ];
      exec = "cargo test";
    };
    # run code review agent on main branch
    "myapp:code-reviewer" = lib.mkIf (github.branch == "main") {
      exec = "claude @code-reviewer";
    };
  };

  # https://devenv.sh/outputs/
  outputs = {
    # package Rust app using Nix
    myapp = config.language.rust.import ./. {};
  };
}

```

## Architecture

- **Backend** (Rust) - REST API server handling authentication, project management, and GitHub webhooks
- **Frontend** (Elm) - Modern web interface built with elm-land for managing environments
- **Runner** (Rust) - WebSocket-connected service for executing commands in remote environments
- **Logger** (Rust) - Centralized logging service for collecting and managing logs
- **Database** (PostgreSQL 17) - Persistent storage with Diesel ORM migrations
- **Authentication** ([Zitadel](https://zitadel.com)) - Open Source OIDC SSO with OAuth2/LDAP/SAML2/OTP support

## Development

1. [Setup Tailscale](https://tailscale.com/kb/1347/installation)

- `tailscale up`
- Enable funnel at https://login.tailscale.com/admin/acls/file
- Copy [DNS](https://login.tailscale.com/admin/dns) that's going to go into `base_url`
- Add `export BASE_URL=...` to `.env`

2. Create [GitHub App](https://github.com/settings/apps/new):

- Name: Choose a unique name for your app (this will be used in config as `app_name`)
- Callback URLs:
  - Legacy zitadel login
    `http://localhost:9500/ui/login/login/externalidp/callback`
  - V2 login UI
    `http://localhost:9500/idps/callback`
- Permissions: Repository: Check (write), Contents (Read)
- Account permissions: read only emails
- Subscribe to events: Pull Request, Check run, Push
- Webhook URL: BASE_URL/api/v1/github/webhook
- Secret: generate secure secret (use this as `webhook_secret` in config)

3. In the GitHub app's general settings:
   - Generate a new private key (use this in config as `app_private_key`)
   - Generate a new client secret
   - Save the client ID and client secret to `.env`.

   ```shell
   export TF_VAR_github_client_id=...
   export TF_VAR_github_client_secret=...
   export TF_VAR_redirect_uris=["http://localhost:1234/", "<BASE_URL>/"]
   ```

4. Create `./cloud.devenv.toml`:

```toml
base_url = "https://<device-name>.<tailnet-name>.ts.net"

[github]
app_name = "your-app-name" # The name of your GitHub app
```

5. Configure development secrets using secretspec:

   ```shell
   secretspec set --provider env GITHUB_APP_PRIVATE_KEY="$(cat path/to/private-key.pem)"
   secretspec set --provider env GITHUB_WEBHOOK_SECRET="your-webhook-secret"
   ```

6. Launch the processes

   ```console
   devenv up
   ```

7. Initialize Zitadel by following `terraform/zitadel/README.md`

8. Set the Zitadel webhook signing key:

   ```shell
   secretspec set --provider env ZITADEL_WEBHOOK_SIGNING_KEY="$(cat .devenv/state/zitadel/signing-key.txt)"
   ```

### Migrations

```
diesel migration generate initial --diff-schema
cargo run -p devenv-backend migrate
```

## Production

1. Generate [PostHog](https://us.posthog.com/login) API key

2. Configure production secrets using secretspec:

```shell
# Required production secrets
secretspec set --provider vault SENTRY_DSN="your-sentry-dsn"
secretspec set --provider vault POSTHOG_API_KEY="your-posthog-api-key"
secretspec set --provider vault DATABASE_URL="your-production-db-url"
secretspec set --provider vault GITHUB_APP_PRIVATE_KEY="$(cat path/to/private-key.pem)"
secretspec set --provider vault GITHUB_WEBHOOK_SECRET="your-webhook-secret"
```
