use std::path::PathBuf;

use clap::{Parser, Subcommand};
use color_eyre::eyre::Result;
use devenv_backend::{config, serve};
use tracing_subscriber::prelude::*;
use utoipa::openapi::License;

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    GenerateElm {
        #[clap(default_value = "cloud.devenv.toml")]
        config_path: PathBuf,
    },
    Migrate {
        #[clap(default_value = "cloud.devenv.toml")]
        config_path: PathBuf,
    },
    Serve {
        #[clap(default_value = "cloud.devenv.toml")]
        config_path: PathBuf,
    },
}

fn main() -> Result<()> {
    rustls::crypto::aws_lc_rs::default_provider()
        .install_default()
        .expect("Failed to set default TLS provider");

    // Setup error handling and tracing
    color_eyre::install()?;
    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer())
        .with(tracing_subscriber::EnvFilter::from_default_env())
        .with(sentry_tracing::layer())
        .with(tracing_error::ErrorLayer::default())
        .init();

    // Parse command line arguments
    let cli = Cli::parse();

    // Process command
    match cli.command {
        Commands::Serve { config_path } => {
            tracing::info!("Starting server with {}", config_path.display());
            let config = config::Config::new(&config_path).map_err(|e| {
                tracing::error!("Failed to load config: {}", e);
                e
            })?;
            serve::main(config)?
        }
        Commands::Migrate { config_path } => {
            tracing::info!("Running migrations with {}", config_path.display());
            let config = config::Config::new(&config_path).map_err(|e| {
                tracing::error!("Failed to load config: {}", e);
                e
            })?;

            // Create runtime
            let runtime = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .map_err(|e| {
                    tracing::error!("Failed to create Tokio runtime: {}", e);
                    eyre::eyre!("Failed to create Tokio runtime: {}", e)
                })?;

            // Run migrations
            runtime.block_on(async {
                let resolved_secrets = config::SecretSpec::builder()
                    .load()
                    .map_err(|e| eyre::eyre!("Failed to load secrets: {}", e))?;
                let app_state = config::AppState::new(config, resolved_secrets.secrets).await?;
                app_state.run_migrations().await
            })?;

            tracing::info!("Migrations completed successfully");
        }
        Commands::GenerateElm { config_path: _ } => {
            tracing::info!("Generating Elm API client");

            // Extract OpenAPI spec
            let (_, mut openapi) = serve::router().split_for_parts();
            openapi.info.license = Some(
                License::builder()
                    .name("CC-BY-SA-4.0")
                    .identifier(Some("CC-BY-SA-4.0"))
                    .build(),
            );

            // Write OpenAPI spec to temp file
            let openapi_json = serde_json::to_string(&openapi)?;
            let tmp_file = tempfile::NamedTempFile::new()?;
            std::fs::write(&tmp_file, openapi_json)?;
            let temp_output_path = PathBuf::from("frontend/generated-api-new");

            // Run OpenAPI generator
            tracing::info!("Running openapi-generator-cli");
            let output = std::process::Command::new("openapi-generator-cli")
                .arg("generate")
                .arg("--input-spec")
                .arg(tmp_file.path())
                .arg("--inline-schema-options")
                // This makes sure inline enums are treated as enums
                .arg("RESOLVE_INLINE_ENUMS=true")
                .arg("--openapi-normalizer")
                // TODO: https://github.com/OpenAPITools/openapi-generator/pull/21041
                .arg("SIMPLIFY_ONEOF_ANYOF=true,SIMPLIFY_ANYOF_STRING_AND_ENUM_STRING=true")
                .arg("--generator-name")
                .arg("elm")
                .arg("--output")
                .arg(&temp_output_path)
                .output()
                .map_err(|e| {
                    tracing::error!("Failed to execute openapi-generator-cli: {}", e);
                    eyre::eyre!("Failed to execute openapi-generator-cli: {}", e)
                })?;

            if !output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let stderr = String::from_utf8_lossy(&output.stderr);
                tracing::error!(
                    "openapi-generator-cli failed:\nstdout: {}\nstderr: {}",
                    stdout,
                    stderr
                );
                return Err(eyre::eyre!("openapi-generator-cli failed"));
            }

            // Patching generated files
            tracing::info!("Patching generated Elm files");

            // Patch Data.elm to support AnyType
            let data_elm_path = temp_output_path.join("src/Api/Data.elm");
            let mut content = std::fs::read_to_string(&data_elm_path)
                .map_err(|e| eyre::eyre!("Failed to read {}: {}", data_elm_path.display(), e))?;

            // Support AnyType: https://github.com/OpenAPITools/openapi-generator/issues/20285
            if !content.contains("AnyType") {
                tracing::info!("Adding AnyType support");
                let additional_code = "\n\ntype alias AnyType = ()\n\nanyTypeDecoder : Json.Decode.Decoder AnyType\nanyTypeDecoder = Json.Decode.succeed ()\n";
                content = content.replace(
                    "module Api.Data exposing\n    ( ",
                    "module Api.Data exposing\n    ( AnyType\n    , anyTypeDecoder\n    , ",
                );
                content.push_str(additional_code);
            }
            std::fs::write(&data_elm_path, content).map_err(|e| {
                eyre::eyre!("Failed to write to {}: {}", data_elm_path.display(), e)
            })?;

            // Patch Api.elm for Request exposure
            let api_elm_path = temp_output_path.join("src/Api.elm");
            let mut content = std::fs::read_to_string(&api_elm_path)
                .map_err(|e| eyre::eyre!("Failed to read {}: {}", api_elm_path.display(), e))?;

            if !content.contains("Request(..)") {
                tracing::info!("Exposing Request constructor");
                content = content.replace("( Request", "( Request(..)");
                std::fs::write(&api_elm_path, content).map_err(|e| {
                    eyre::eyre!("Failed to write to {}: {}", api_elm_path.display(), e)
                })?;
            }

            // Replace old directory with new one
            let final_path = PathBuf::from("frontend/generated-api");
            tracing::info!("Moving generated files to {}", final_path.display());

            if final_path.exists() {
                std::fs::remove_dir_all(&final_path).map_err(|e| {
                    eyre::eyre!(
                        "Failed to remove old directory {}: {}",
                        final_path.display(),
                        e
                    )
                })?;
            }

            std::fs::rename(&temp_output_path, &final_path).map_err(|e| {
                eyre::eyre!(
                    "Failed to move new files to {}: {}",
                    final_path.display(),
                    e
                )
            })?;

            tracing::info!("Elm API client generation completed successfully");
        }
    };

    tracing::info!("devenv-backend completed successfully");
    Ok(())
}
