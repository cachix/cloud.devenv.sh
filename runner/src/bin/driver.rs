use color_eyre::eyre::{Result, WrapErr, eyre};
use devenv::{Devenv, DevenvOptions, GlobalOptions, config};
use devenv_runner::protocol::JobConfig;
use devenv_runner::vsock::{self, VsockWriter};
use gix::remote::fetch::Shallow;
#[cfg(target_os = "linux")]
use nix::unistd::{Gid, Uid, setgid, setuid};
#[cfg(target_os = "linux")]
use pid1::Pid1Settings;
use std::num::NonZeroU32;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing_subscriber::prelude::*;

// Embed cloud.nix file into the binary
const CLOUD_NIX: &str = include_str!("../cloud.nix");

// Directory to clone the repository into
#[cfg(target_os = "linux")]
const PROJECT_DIR: &str = "/home/devenv";

#[cfg(target_os = "macos")]
const PROJECT_DIR: &str = "/Users/admin/devenv";

#[tokio::main]
async fn main() -> Result<()> {
    color_eyre::install()?;

    // Initialize pid1 handling for Linux
    #[cfg(target_os = "linux")]
    {
        Pid1Settings::new()
            .enable_log(true)
            .launch()
            .wrap_err("Failed to initialize PID 1 handling")?;
    }

    // Connect to vsock and set up logging FIRST, before any operations that might fail
    // This ensures we capture all logs even if the driver fails early
    let (job_config, reporter) = vsock::receive_config_from_host()
        .await
        .wrap_err("Failed to receive job configuration over vsock")?;

    // Set up tracing to send JSON logs over vsock
    let reporter_arc = Arc::new(Mutex::new(reporter));
    let reporter_for_tracing = reporter_arc.clone();

    // Create a writer that sends JSON logs through vsock
    let vsock_writer = VsockWriter::new(reporter_for_tracing);

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::fmt::layer()
                .json()
                .with_writer(move || vsock_writer.clone())
                .with_target(true)
                .with_thread_ids(false)
                .with_thread_names(false)
                .with_file(true)
                .with_line_number(true),
        )
        .init();

    tracing::debug!("Received job configuration: {:?}", job_config);

    // Set up Nix for single-user mode on Linux
    #[cfg(target_os = "linux")]
    {
        // Configure network on Linux
        tracing::info!("Configuring network...");
        devenv_runner::vm_impl::linux_networking::configure_network().await?;

        // Read the nix binary path from the file created during build
        let nix_binary_path_file = PathBuf::from("/nix-binary-path");
        let nix_store_path = if nix_binary_path_file.exists() {
            std::fs::read_to_string(&nix_binary_path_file)
                .wrap_err("Failed to read nix-binary-path file")?
                .trim()
                .to_string()
        } else {
            return Err(eyre!(
                "nix-binary-path file not found at: {}",
                nix_binary_path_file.display()
            ));
        };

        tracing::debug!("Setting DEVENV_NIX to: {}", nix_store_path);
        unsafe {
            std::env::set_var("DEVENV_NIX", &nix_store_path);
        }

        // Set PATH to /bin after we've resolved the nix path
        unsafe {
            std::env::set_var("PATH", "/bin");
        }

        // Create Nix directories as root
        std::fs::create_dir_all("/nix/var/nix/db")?;
        std::fs::create_dir_all("/nix/var/nix/profiles")?;
        std::fs::create_dir_all("/nix/var/nix/gcroots")?;
        std::fs::create_dir_all("/nix/var/nix/temproots")?;
        std::fs::create_dir_all("/nix/var/log/nix")?;

        // Change ownership of /nix to devenv user before loading database
        let output = std::process::Command::new("chown")
            .args(["-R", "1000:100", "/nix"])
            .output()
            .wrap_err("Failed to change ownership of /nix")?;

        if !output.status.success() {
            return Err(eyre!(
                "Failed to chown /nix: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        // Load the Nix database from registration file as root
        let nix_store_binary = PathBuf::from(&nix_store_path).join("bin/nix-store");

        let output = std::process::Command::new(&nix_store_binary)
            .arg("--load-db")
            .stdin(std::fs::File::open("/registration")?)
            .output()
            .wrap_err("Failed to load Nix database")?;

        if !output.status.success() {
            return Err(eyre!(
                "Failed to load Nix database: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        // Final chown to ensure devenv owns everything including the newly created database
        let output = std::process::Command::new("chown")
            .args(["-R", "1000:100", "/nix"])
            .output()
            .wrap_err("Failed to change ownership of /nix after loading database")?;

        if !output.status.success() {
            return Err(eyre!(
                "Failed to chown /nix after loading database: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }
    }

    // Get project directory path
    let project_dir = PathBuf::from(PROJECT_DIR);

    // Drop privileges to devenv user on Linux
    #[cfg(target_os = "linux")]
    {
        let devenv_uid = Uid::from_raw(1000);
        let devenv_gid = Gid::from_raw(100); // Using GID 100 to match virtiofs behavior

        tracing::debug!("Dropping privileges to devenv user (uid=1000, gid=100)");
        setgid(devenv_gid).wrap_err("Failed to set group ID for devenv user")?;
        setuid(devenv_uid).wrap_err("Failed to set user ID for devenv user")?;
    }

    // Create project directory as devenv user
    std::fs::create_dir_all(&project_dir)
        .wrap_err_with(|| format!("Failed to create {} as devenv user", project_dir.display()))?;

    // Clone or update the repository as devenv user
    clone_repository(&job_config, &project_dir)?;

    // Set up and run devenv
    let job_result = run_devenv(&job_config, &project_dir).await;

    // Log the error if devenv failed
    if let Err(e) = &job_result {
        tracing::error!("Devenv execution failed: {:?}", e);
    }

    // Report job completion status
    {
        let mut reporter_guard = reporter_arc.lock().await;
        if let Err(e) = reporter_guard.report_complete(job_result.is_ok()).await {
            tracing::error!("Failed to report job completion to host: {:?}", e);
        }
    }

    // Cleanly shutdown the VM regardless of success or failure
    tracing::info!("Shutting down VM");

    #[cfg(target_os = "linux")]
    unsafe {
        // Sync filesystem data before shutdown
        libc::sync();
        // Initiate system shutdown
        libc::reboot(libc::RB_HALT_SYSTEM);
    }

    #[cfg(target_os = "macos")]
    {
        // On macOS, use the shutdown command
        std::process::Command::new("sudo")
            .args(&["shutdown", "-h", "now"])
            .spawn()
            .ok();
    }

    // Return the result
    job_result
}

/// Clone the repository using gix
fn clone_repository(job_config: &JobConfig, project_dir: &PathBuf) -> Result<()> {
    tracing::info!(
        "Cloning repository from {} into {}",
        job_config.project_url,
        project_dir.display()
    );

    // Set up SSL certificate environment variables for HTTPS
    let cert_path = "/etc/ssl/certs/ca-bundle.crt";

    // Only set defaults if env vars aren't already set
    if std::env::var("SSL_CERT_FILE").is_err() {
        if std::path::Path::new(cert_path).exists() {
            unsafe {
                std::env::set_var("SSL_CERT_FILE", cert_path);
            }
        } else {
            return Err(eyre!(
                "SSL_CERT_FILE not set and default cert file doesn't exist"
            ));
        }
    }

    if std::env::var("NIX_SSL_CERT_FILE").is_err() {
        if std::path::Path::new(cert_path).exists() {
            unsafe {
                std::env::set_var("NIX_SSL_CERT_FILE", cert_path);
            }
        } else {
            return Err(eyre!(
                "NIX_SSL_CERT_FILE not set and default cert file doesn't exist"
            ));
        }
    }

    // Prepare the clone operation
    let mut prepare_clone = gix::prepare_clone(job_config.project_url.as_str(), project_dir)
        .wrap_err("Failed to prepare repository clone")?;

    // Configure shallow clone with specified depth if provided
    if let Some(depth) = job_config.clone_depth.and_then(NonZeroU32::new) {
        prepare_clone = prepare_clone.with_shallow(Shallow::DepthAtRemote(depth));
    }

    // Configure to checkout specific ref if provided
    if let Some(git_ref) = &job_config.git_ref {
        tracing::info!("Checking out ref {}", git_ref);
        prepare_clone = prepare_clone
            .with_ref_name(Some(git_ref.as_str()))
            .wrap_err_with(|| format!("Invalid git ref '{}'", git_ref))?;
    }

    // Fetch and prepare for checkout
    let (mut prepare_checkout, _outcome) = prepare_clone
        .fetch_then_checkout(gix::progress::Discard, &gix::interrupt::IS_INTERRUPTED)
        .wrap_err("Failed to fetch repository")?;

    // Perform the checkout to main worktree
    let (_repo, _outcome) = prepare_checkout
        .main_worktree(gix::progress::Discard, &gix::interrupt::IS_INTERRUPTED)
        .wrap_err("Failed to checkout repository")?;

    tracing::info!("Repository cloned successfully");

    Ok(())
}

/// Set up and run devenv with the provided configuration
async fn run_devenv(job_config: &JobConfig, project_dir: &PathBuf) -> Result<()> {
    // Ensure we have an absolute path
    let project_dir = project_dir
        .canonicalize()
        .unwrap_or_else(|_| project_dir.clone());

    tracing::info!("Loading devenv config from: {:?}", project_dir);

    // Change to the project directory
    std::env::set_current_dir(&project_dir).wrap_err("Failed to change to project directory")?;

    // Load configuration from current directory
    let devenv_config = config::Config::load_from(&project_dir)
        .map_err(|e| eyre!("Failed to load devenv config: {:?}", e))?;

    // Create temporary cloud.nix file
    let temp_dir = tempfile::tempdir()?;
    let cloud_nix_path = temp_dir.path().join("cloud.nix");
    std::fs::write(&cloud_nix_path, CLOUD_NIX)?;

    // TODO: Add cloud.nix to imports
    // devenv_config
    //     .imports
    //     .push(cloud_nix_path.to_string_lossy().to_string());

    // Configure options
    let global_options = GlobalOptions::default();

    if job_config.cachix_push {
        tracing::info!("Enabling Cachix push");
        // TODO: Set up Cachix push options here
    }

    // Create DevenvOptions
    let options = DevenvOptions {
        config: devenv_config,
        global_options: Some(global_options),
        devenv_root: Some(project_dir.clone()),
        devenv_dotfile: None, // Default will be used (.devenv)
    };

    // Create and initialize Devenv instance
    let devenv = Devenv::new(options).await;

    // Assemble the environment
    tracing::info!("Assembling devenv environment");
    devenv
        .assemble(false)
        .await
        .map_err(|e| eyre!("Failed to assemble devenv: {:?}", e))?;

    // Build the shell
    tracing::info!("Building devenv shell");
    devenv
        .build(&["shell".to_string()])
        .await
        .map_err(|e| eyre!("Failed to build devenv shell: {:?}", e))?;

    Ok(())
}
