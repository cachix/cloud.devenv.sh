use color_eyre::eyre::Result;
use devenv_runner::config::VmConfig;
use devenv_runner::protocol::{JobConfig, Platform, VM};
use devenv_runner::resource_manager::ResourceManager;
use devenv_runner::vm_manager::{VmCompletionEvent, VmManager};
use signal_hook::consts::signal::{SIGINT, SIGQUIT, SIGTERM};
use signal_hook::iterator::Signals;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing_subscriber::prelude::*;
use uuid::Uuid;

#[tokio::main]
async fn main() -> Result<()> {
    color_eyre::install()?;

    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Setup host networking for VMs on Linux
    #[cfg(target_os = "linux")]
    {
        use devenv_runner::vm_impl::linux_networking;
        linux_networking::setup_host_networking()
            .expect("Failed to setup host networking. This typically requires root privileges.");
    }

    // Set up VM configuration based on platform
    let platform = if cfg!(target_os = "macos") {
        Platform::AArch64Darwin
    } else if cfg!(target_os = "linux") {
        Platform::X86_64Linux
    } else {
        return Err(color_eyre::eyre::eyre!("Unsupported platform"));
    };

    // Same VM configuration for both platforms
    let vm_config = VM {
        cpu_count: 2,
        memory_size_mb: 8192,
        platform,
    };

    let job_id = Uuid::now_v7();

    tracing::info!("Creating VM with config: {:?}", vm_config);

    // Create a resource manager for the launcher
    let resource_manager = Arc::new(ResourceManager::with_platform_defaults());

    // Load VM runtime configuration from environment
    let runner_config = VmConfig {
        resources_dir: PathBuf::from(
            std::env::var("RESOURCES_DIR").expect("RESOURCES_DIR environment variable must be set"),
        ),
        state_dir: PathBuf::from(
            std::env::var("DEVENV_STATE").expect("DEVENV_STATE environment variable must be set"),
        ),
    };

    // Create VM completion channel
    let (completion_tx, mut completion_rx) = mpsc::channel::<VmCompletionEvent>(10);

    // Create VM manager - this will clean up old VM directories on Linux
    let vm_manager = Arc::new(VmManager::new(
        completion_tx,
        resource_manager.clone(),
        runner_config,
    ));

    // Create a sample job configuration
    let job_config = JobConfig {
        id: job_id,
        project_url: "https://github.com/cachix/devenv".to_string(),
        git_ref: Some("main".to_string()),
        tasks: vec!["build".to_string()],
        cachix_push: false,
        clone_depth: Some(1),
    };

    tracing::info!("Setting job configuration: {:?}", job_config);

    // Create a log channel (for testing, we'll just log to console)
    let (log_sender, mut log_receiver) = mpsc::channel::<String>(100);

    // Spawn a task to handle logs
    tokio::spawn(async move {
        while let Some(log) = log_receiver.recv().await {
            tracing::info!("VM Log: {}", log);
        }
    });

    // Launch VM using VmManager
    vm_manager
        .launch_vm(job_id, vm_config, job_config, log_sender)
        .await?;

    // Set up signal handling
    let mut signals = Signals::new([SIGTERM, SIGINT, SIGQUIT])?;

    // Handle platform-specific behavior
    #[cfg(target_os = "macos")]
    {
        // On macOS, we need to create a separate thread for signal handling
        // and we use dispatch_main() to keep the process running

        // Create a channel to communicate VM shutdown
        let (shutdown_tx, mut shutdown_rx) = tokio::sync::mpsc::channel::<()>(1);

        // Clone vm_manager for shutdown
        let vm_manager_clone = vm_manager.clone();

        // Spawn a task to handle signals and send shutdown request
        tokio::task::spawn(async move {
            if let Some(SIGTERM | SIGINT | SIGQUIT) = signals.forever().next() {
                tracing::info!("Received shutdown signal");
                let _ = shutdown_tx.send(()).await;
            }
        });

        // Spawn a task to monitor VM completion and handle shutdown
        tokio::task::spawn(async move {
            tokio::select! {
                _ = shutdown_rx.recv() => {
                    tracing::info!("Shutdown requested, stopping VM");
                    let _ = vm_manager_clone.shutdown_vm(&job_id).await;
                    std::process::exit(0);
                }
                Some(event) = completion_rx.recv() => {
                    tracing::info!("VM exited with status: {:?}", event.status);
                    match event.status {
                        devenv_runner::vm::VmExitStatus::Success => {
                            tracing::info!("Job completed successfully! ✓");
                            std::process::exit(0);
                        }
                        devenv_runner::vm::VmExitStatus::Failure => {
                            tracing::error!("Job failed! ✗");
                            std::process::exit(1);
                        }
                    }
                }
            }
        });

        // Run the GCD runloop - this doesn't return
        tracing::info!("Starting macOS dispatch loop");
        dispatch2::dispatch_main()
    }

    // Handle Linux
    #[cfg(not(target_os = "macos"))]
    {
        // On Linux, we can use tokio::select! to wait for either signals or VM completion
        // Use a flag to track if we need to shutdown
        let shutdown_flag = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let shutdown_flag_clone = shutdown_flag.clone();

        // Spawn a separate task to handle signals
        let signal_task = tokio::spawn(async move {
            if let Some(SIGTERM | SIGINT | SIGQUIT) = signals.forever().next() {
                tracing::info!("Received shutdown signal");
                shutdown_flag_clone.store(true, std::sync::atomic::Ordering::SeqCst);
            }
        });

        // Wait for VM completion or shutdown signal
        let exit_code = tokio::select! {
            // Wait for VM completion event
            Some(event) = completion_rx.recv() => {
                tracing::info!("VM exited with status: {:?}", event.status);
                match event.status {
                    devenv_runner::vm::VmExitStatus::Success => {
                        tracing::info!("Job completed successfully! ✓");
                        0
                    }
                    devenv_runner::vm::VmExitStatus::Failure => {
                        tracing::error!("Job failed! ✗");
                        1
                    }
                }
            }
            // Wait for shutdown signal
            _ = async {
                loop {
                    if shutdown_flag.load(std::sync::atomic::Ordering::SeqCst) {
                        break;
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                }
            } => {
                tracing::info!("Shutdown requested, stopping VM");
                let _ = vm_manager.shutdown_vm(&job_id).await;
                // Wait for VM completion after shutdown
                match completion_rx.recv().await {
                    Some(event) => match event.status {
                        devenv_runner::vm::VmExitStatus::Success => 0,
                        devenv_runner::vm::VmExitStatus::Failure => 1,
                    },
                    None => 1,
                }
            }
        };

        // Clean up signal task
        let _ = signal_task.abort();

        // Ensure the process exits cleanly by calling std::process::exit
        // This is necessary because background tasks (like the vsock server) might
        // still be running and preventing the tokio runtime from shutting down
        std::process::exit(exit_code);
    }
}
