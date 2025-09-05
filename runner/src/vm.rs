use crate::protocol::{CompletionStatus, JobConfig, VM};
use crate::resource_manager::ResourceManager;
use eyre::Result;
use std::path::PathBuf;
use std::sync::Arc;

/// Represents the exit status of a VM
#[derive(Debug, Clone, Copy)]
pub enum VmExitStatus {
    /// VM exited successfully (exit code 0)
    Success,
    /// VM exited with an error (non-zero exit code)
    Failure,
}

impl From<VmExitStatus> for CompletionStatus {
    fn from(status: VmExitStatus) -> Self {
        match status {
            VmExitStatus::Success => CompletionStatus::Success,
            VmExitStatus::Failure => CompletionStatus::Failed,
        }
    }
}

/// Trait defining the interface for VM operations
#[async_trait::async_trait]
pub trait Vm: Send {
    /// Create a new VM with the given configuration
    async fn new(vm_config: VM, id: String, resource_manager: Arc<ResourceManager>) -> Result<Self>
    where
        Self: Sized;

    async fn start(&mut self) -> Result<()>;

    /// Wait for the VM process to finish
    async fn wait(&mut self) -> Result<VmExitStatus>;

    /// Shut down the VM
    async fn shutdown(&mut self) -> Result<()>;

    /// Get the VM configuration
    fn config(&self) -> &VM;

    /// Get the VM identifier
    fn id(&self) -> &str;

    /// Get the runtime directory
    fn run_dir(&self) -> &PathBuf;

    /// Set job configuration and send it to the guest over vsock
    async fn set_job_config(
        &mut self,
        job_config: JobConfig,
        log_sender: tokio::sync::mpsc::Sender<String>,
    ) -> Result<()>;
}

/// Create a platform-specific VM instance
pub async fn create_vm(
    vm_config: VM,
    id: String,
    resource_manager: Arc<ResourceManager>,
) -> Result<Box<dyn Vm>> {
    #[cfg(target_os = "macos")]
    {
        let vm = crate::vm_impl::macos::MacosVm::new(vm_config, id, resource_manager).await?;
        Ok(Box::new(vm))
    }

    #[cfg(target_os = "linux")]
    {
        let vm = crate::vm_impl::linux::LinuxVm::new(vm_config, id, resource_manager).await?;
        Ok(Box::new(vm))
    }

    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    {
        Err(eyre::eyre!("Unsupported platform"))
    }
}

/// Detect if we're running on macOS
pub fn is_macos() -> bool {
    cfg!(target_os = "macos")
}

/// Detect if we're running on Linux
pub fn is_linux() -> bool {
    cfg!(target_os = "linux")
}
