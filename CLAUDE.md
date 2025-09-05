# CLAUDE.md - Developer Guide for cloud.devenv.sh

@docs/sql-naming-conventions.md

## Build & Development Commands

- Always assume we're running `devenv up` in separate window and all services restart on change
- `cargo build --workspace` - Build Rust (always run first)
- `elm-land build` - Build Elm/frontend
- `pre-commit run --all-files` - Run all formatters/linters
- `psql devenv` - Launch Postgres client
- `diesel migration generate <name> --diff-schema` - Generate migration
- `cargo run -p devenv-backend migrate` - Run database migrations

## Code Style Guidelines

### Rust

- Look up crate documentation at https://doc.rs/{crate} for Rust
- Naming: snake_case for variables/functions, PascalCase for types/traits
- Errors: Use thiserror for custom errors with #[derive(Error, Debug)]
- Imports: Ordered by std → external → local, alphabetically within groups
- Return Results with custom error types or Report wrapper
- 4-space indentation, trailing commas in multi-line structures
- no `unsafe` code
- no SQL queries in `serve.rs`, they should go to `model.rs`

### Elm

- Look up documenatation at https://package.elm-lang.org/packages/{prefix}/{package}/latest/
- Naming: camelCase for variables/functions, PascalCase for types/modules
- Use RemoteData pattern for API calls and loading states
- Builder pattern with "with" functions for component configuration
- Structure modules with explicit exports and types at the top
- Consistent view helper functions for rendering logic
- everything in `frontend/generated-api` is generated, assume it will get updated, the API is in `frontend/generated-api/src/Api/Data.elm`.

### General

- Strive to make most of operations using joins on database instead of application logic
- Write comprehensive docstring comments for public functions
- Commit small, focused changes with descriptive messages
- Run tests and linters before submitting code
