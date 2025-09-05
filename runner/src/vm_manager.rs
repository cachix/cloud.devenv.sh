use crate::protocol::{JobConfig, VM};
use crate::resource_manager::ResourceManager;
use crate::vm::VmExitStatus;
use eyre::Result;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{RwLock, mpsc};
use tracing;
use uuid::Uuid;

/// Commands to control VMs
#[derive(Debug)]
pub enum VmCommand {
    Shutdown,
}

/// Event emitted when a VM completes
#[derive(Debug, Clone)]
pub struct VmCompletionEvent {
    pub job_id: Uuid,
    pub status: VmExitStatus,
}

/// VM Manager that handles VM lifecycle
pub struct VmManager {
    // Map of job ID to control channel
    control_channels: Arc<RwLock<HashMap<Uuid, mpsc::Sender<VmCommand>>>>,
    // Channel for VM completion events
    completion_tx: mpsc::Sender<VmCompletionEvent>,
    // Resource manager for IP allocation (Linux only)
    resource_manager: Arc<ResourceManager>,
}

impl VmManager {
    pub fn new(
        completion_tx: mpsc::Sender<VmCompletionEvent>,
        resource_manager: Arc<ResourceManager>,
    ) -> Self {
        Self {
            control_channels: Arc::new(RwLock::new(HashMap::new())),
            completion_tx,
            resource_manager,
        }
    }

    /// Launch a VM for a job
    pub async fn launch_vm(
        &self,
        job_id: Uuid,
        vm_config: VM,
        job_config: JobConfig,
        log_sender: mpsc::Sender<String>,
    ) -> Result<()> {
        // Create control channel for this VM
        let (control_tx, control_rx) = mpsc::channel::<VmCommand>(10);

        // Register the control channel
        {
            let mut channels = self.control_channels.write().await;
            channels.insert(job_id, control_tx);
        }

        // Prepare for VM monitoring task
        let completion_tx = self.completion_tx.clone();
        let control_channels = self.control_channels.clone();
        let resource_manager = self.resource_manager.clone();

        // Launch VM in background - use dedicated thread on macOS for dispatch queues
        #[cfg(target_os = "macos")]
        {
            std::thread::spawn(move || {
                // Create a tokio runtime for this thread to handle async operations
                let rt = tokio::runtime::Runtime::new()
                    .expect("Failed to create tokio runtime for VM thread");
                rt.block_on(async move {
                    vm_task_impl(
                        job_id,
                        vm_config,
                        job_config,
                        completion_tx,
                        control_channels,
                        resource_manager,
                        control_rx,
                        log_sender,
                    )
                    .await;
                });
            });
        }

        #[cfg(not(target_os = "macos"))]
        {
            tokio::spawn(async move {
                vm_task_impl(
                    job_id,
                    vm_config,
                    job_config,
                    completion_tx,
                    control_channels,
                    resource_manager,
                    control_rx,
                    log_sender,
                )
                .await;
            });
        }

        Ok(())
    }

    /// Shut down a VM for a job
    pub async fn shutdown_vm(&self, job_id: &Uuid) -> Result<bool> {
        let control_tx = {
            let channels = self.control_channels.read().await;
            channels.get(job_id).cloned()
        };

        if let Some(tx) = control_tx {
            tx.send(VmCommand::Shutdown)
                .await
                .map_err(|e| eyre::eyre!("Failed to send shutdown command: {}", e))?;
            Ok(true)
        } else {
            // VM not found or already shut down
            Ok(false)
        }
    }

    /// Check if a job's VM is still running
    pub async fn is_vm_running(&self, job_id: &Uuid) -> bool {
        let channels = self.control_channels.read().await;
        channels.contains_key(job_id)
    }
}

impl Drop for VmManager {
    fn drop(&mut self) {
        // Cleanup VM template directories on shutdown (Linux only)
        #[cfg(target_os = "linux")]
        {
            tracing::info!("VmManager dropping, cleaning up VM template directories");
            if let Err(e) = crate::vm_impl::linux::cleanup_vm_template() {
                tracing::warn!(
                    "Failed to cleanup VM template directories on shutdown: {}",
                    e
                );
            }
        }
    }
}

// Extract the VM task implementation into a separate function
async fn vm_task_impl(
    job_id: Uuid,
    vm_config: VM,
    job_config: JobConfig,
    completion_tx: mpsc::Sender<VmCompletionEvent>,
    control_channels: Arc<RwLock<HashMap<Uuid, mpsc::Sender<VmCommand>>>>,
    resource_manager: Arc<ResourceManager>,
    mut control_rx: mpsc::Receiver<VmCommand>,
    log_sender: mpsc::Sender<String>,
) {
    // Create and start VM
    let vm_result = async {
        let mut vm = crate::vm::create_vm(vm_config, job_id.to_string(), resource_manager).await?;

        // Set job configuration (send to guest)
        vm.set_job_config(job_config, log_sender).await?;

        // Start VM
        vm.start().await?;

        Ok::<_, eyre::Report>(vm)
    }
    .await;

    match vm_result {
        Ok(mut vm) => {
            // Wait for VM exit or shutdown command
            let exit_status = {
                tokio::select! {
                    // VM exited naturally
                    status = vm.wait() => {
                        status.unwrap_or(VmExitStatus::Failure)
                    }
                    // Control command received
                    Some(cmd) = control_rx.recv() => {
                        match cmd {
                            VmCommand::Shutdown => {
                                tracing::info!("Received shutdown command for VM {}", job_id);

                                // Try to shut down VM gracefully
                                if let Err(e) = vm.shutdown().await {
                                    tracing::error!("Failed to shut down VM: {}", e);
                                }

                                // Wait for VM to exit naturally after shutdown
                                // without a timeout - wait as long as needed
                                match vm.wait().await {
                                    Ok(status) => status,
                                    Err(e) => {
                                        tracing::error!("Error waiting for VM to exit: {}", e);
                                        VmExitStatus::Failure
                                    }
                                }
                            }
                        }
                    }
                }
            };

            // Send completion event
            let _ = completion_tx
                .send(VmCompletionEvent {
                    job_id,
                    status: exit_status,
                })
                .await;
        }
        Err(e) => {
            // VM creation failed - the IP guard will automatically release the IP when dropped
            tracing::error!("Failed to create VM for job {}: {}", job_id, e);
            let _ = completion_tx
                .send(VmCompletionEvent {
                    job_id,
                    status: VmExitStatus::Failure,
                })
                .await;
        }
    }

    // Clean up control channel
    let mut channels = control_channels.write().await;
    channels.remove(&job_id);

    // The IP guard will automatically release the IP when it goes out of scope
    // The resource_guard will automatically release CPU/memory resources when it goes out of scope
}
