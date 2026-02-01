# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@docs/sql-naming-conventions.md

## Build & Development Commands

- Always assume `devenv up` is running in a separate window (services auto-restart on change)
- `cargo build --workspace` - Build all Rust crates (always run first)
- `cargo test --workspace` - Run all Rust tests
- `cargo test -p devenv-backend` - Run tests for a specific crate
- `elm-land build` - Build Elm frontend
- `pre-commit run --all-files` - Run all formatters/linters
- `psql devenv` - Launch Postgres client
- `diesel migration generate <name> --diff-schema` - Generate migration from schema changes
- `cargo run -p devenv-backend migrate` - Run database migrations
- `cargo run -p devenv-backend generate-elm` - Regenerate Elm API client from OpenAPI spec

## Architecture

### Services (all start via `devenv up`)

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Frontend   │     │   Backend   │     │   Logger    │
│  (Elm)      │────▶│   (Axum)    │────▶│  (SlateDB)  │
│  :1234      │     │   :8080     │     │   :3000     │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                    ┌──────┴──────┐
                    │             │
              ┌─────▼─────┐ ┌─────▼─────┐
              │  Zitadel  │ │  Runner   │
              │  (Auth)   │ │  (VMs)    │
              │  :9500    │ │  WebSocket│
              └───────────┘ └───────────┘
```

### Backend Module Structure (backend/src/)

Each domain follows the pattern: `mod.rs` (exports), `model.rs` (database queries), `serve.rs` (HTTP handlers)

- `github/` - GitHub App webhooks, check runs, OAuth. `integration.rs` wraps octocrab API calls
- `job/` - CI job lifecycle management
- `runner/` - WebSocket coordination with VM runners
- `account/` - User account management
- `zitadel/` - Authentication webhooks and actions
- `auth.rs` - JWT token validation middleware
- `schema.rs` - Diesel database schema (auto-generated)

### Runner (runner/src/)

Executes CI jobs in isolated VMs:

- `vm_impl/linux.rs` - Cloud Hypervisor backend (Linux/KVM)
- `vm_impl/macos.rs` - Apple Virtualization framework
- `job_manager.rs` - Job execution lifecycle
- `vsock.rs` - VM communication via virtio-vsock

### Frontend (frontend/)

- Built with elm-land framework
- `src/Pages/` - Route pages
- `src/Components/` - Reusable UI components
- `generated-api/` - Auto-generated from backend OpenAPI spec (do not edit manually)

## Code Style Guidelines

### Rust

- Look up crate documentation at https://doc.rs/{crate}
- Naming: snake_case for variables/functions, PascalCase for types/traits
- Errors: Use thiserror for custom errors with `#[derive(Error, Debug)]`
- Imports: Ordered by std → external → local, alphabetically within groups
- Return Results with custom error types or Report wrapper
- 4-space indentation, trailing commas in multi-line structures
- No `unsafe` code
- No SQL queries in `serve.rs` - they belong in `model.rs`

### Elm

- Look up documentation at https://package.elm-lang.org/packages/{prefix}/{package}/latest/
- Naming: camelCase for variables/functions, PascalCase for types/modules
- Use RemoteData pattern for API calls and loading states
- Builder pattern with "with" functions for component configuration
- Structure modules with explicit exports and types at the top
- Everything in `frontend/generated-api` is auto-generated from the backend API

### General

- Prefer database joins over application-level data combining
- Write docstring comments for public functions
