use crate::config::VmConfig as RunnerVmConfig;
use crate::protocol::{JobConfig, VM};
use crate::resource_manager::{CidGuard, IpGuard, ResourceGuard, ResourceManager};
use crate::vm::Vm;
use crate::vsock;
use cloud_hypervisor_client::apis::client::APIClient;
use cloud_hypervisor_client::apis::configuration::Configuration;
use cloud_hypervisor_client::models::console_config::Mode;
use cloud_hypervisor_client::models::{
    ConsoleConfig, CpusConfig, FsConfig, MemoryConfig, NetConfig, PayloadConfig, VmConfig,
    VsockConfig,
};
use eyre::{Result, WrapErr};
use fs_extra::dir::{self, CopyOptions};
use std::fs::create_dir_all;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing;

use super::linux_networking::{VM_GATEWAY_IP, VM_SUBNET_MASK};

/// Platform-specific resources needed for VM creation on Linux
pub struct VmResources {
    pub kernel_path: PathBuf,
    pub initrd_path: PathBuf,
}

/// Linux implementation of VM provider
pub struct LinuxVm {
    /// The VM configuration
    config: VM,
    /// Resource guard for automatic resource release (kept alive for RAII cleanup)
    _resource_guard: Option<ResourceGuard>,
    /// IP guard for automatic IP release (kept alive for RAII cleanup)
    _ip_guard: Option<IpGuard>,
    /// CID guard for automatic CID release (kept alive for RAII cleanup)
    _cid_guard: Option<CidGuard>,
    /// The VM identifier
    id: String,
    /// The runtime directory for VM-related files (as TempDir for auto-cleanup)
    _run_dir_temp: tempfile::TempDir,
    /// Path to the runtime directory (cached for trait compliance)
    run_dir: PathBuf,
    /// The cloud-hypervisor API client
    client: APIClient,
    /// The cloud-hypervisor process handle
    process: Child,
    /// Job configuration if available
    job_config: Option<JobConfig>,
    /// Process handle for virtiofsd, if using shared filesystem
    virtiofsd_process: Option<Child>,
    /// Directory containing the VM's root filesystem
    vm_rootfs_dir: PathBuf,
    /// Shared state for job result from vsock
    job_result: Arc<Mutex<Option<bool>>>,
    /// Join handle for the vsock server task
    vsock_server_handle: Option<tokio::task::JoinHandle<()>>,
}

impl Drop for LinuxVm {
    fn drop(&mut self) {
        tracing::info!("Dropping LinuxVm {}, cleaning up processes...", self.id);

        // Abort the vsock server task if it's still running
        if let Some(handle) = self.vsock_server_handle.take() {
            handle.abort();
        }

        // Kill the cloud-hypervisor process
        if let Err(e) = self.process.kill() {
            if !matches!(e.kind(), std::io::ErrorKind::InvalidInput) {
                tracing::warn!("Failed to kill VM process for {}: {}", self.id, e);
            }
        }

        // Kill virtiofsd process if it exists
        if let Some(virtiofsd) = &mut self.virtiofsd_process {
            if let Err(e) = virtiofsd.kill() {
                if !matches!(e.kind(), std::io::ErrorKind::InvalidInput) {
                    tracing::warn!("Failed to kill virtiofsd process for {}: {}", self.id, e);
                }
            }
        }

        // Wait briefly for processes to terminate
        std::thread::sleep(std::time::Duration::from_millis(100));

        // Clean up VM rootfs directory
        if let Err(e) = std::fs::remove_dir_all(&self.vm_rootfs_dir) {
            tracing::warn!(
                "Failed to remove VM rootfs directory {:?}: {}",
                self.vm_rootfs_dir,
                e
            );
        } else {
            tracing::info!("Cleaned up VM rootfs directory {:?}", self.vm_rootfs_dir);
        }
    }
}

#[async_trait::async_trait]
impl Vm for LinuxVm {
    /// Create a new VM with the given configuration
    async fn new(
        vm_config: VM,
        id: String,
        resource_manager: Arc<ResourceManager>,
        config: &RunnerVmConfig,
    ) -> Result<Self> {
        // Create a temporary directory for this VM (will be auto-cleaned on drop)
        let run_dir_temp =
            tempfile::tempdir().wrap_err("Failed to create temporary runtime directory")?;
        let run_dir = run_dir_temp.path().to_path_buf();

        // Allocate resources for the VM
        let job_id = uuid::Uuid::now_v7(); // Generate a unique job ID for this VM
        let resource_guard = resource_manager
            .allocate_resources(job_id, vm_config.clone())
            .await
            .map_err(|e| eyre::eyre!("Failed to allocate resources for VM {}: {:?}", id, e))?;

        let resources = VmResources {
            kernel_path: config.resources_dir.join("vmlinux"),
            initrd_path: config.resources_dir.join("initrd"),
        };

        // Create VM storage directory
        let vm_storage_base = config.state_dir.join("vms");
        create_dir_all(&vm_storage_base).wrap_err("Failed to create VM storage base directory")?;

        let vm_rootfs_dir = vm_storage_base.join(&id);
        create_dir_all(&vm_rootfs_dir).wrap_err("Failed to create VM rootfs directory")?;
        let nix_store_dir = vm_rootfs_dir.join("nix").join("store");

        // Use rootfs directory from resources
        let rootfs_dir = config.resources_dir.join("rootfs");

        tracing::info!("Preparing VM rootfs directory {}", vm_rootfs_dir.display());

        // Copy rootfs to VM directory
        let mut copy_options = CopyOptions::new();
        copy_options.content_only = true;

        dir::copy(&rootfs_dir, &vm_rootfs_dir, &copy_options)
            .wrap_err("Failed to copy rootfs directory to VM rootfs dir")?;

        // Get the path to the pre-built nix store image
        let nix_store_image_path = config.resources_dir.join("nix-store-image");
        let nix_store_source = nix_store_image_path.join("nix/store");

        // Create the nix directory structure
        create_dir_all(&nix_store_dir).wrap_err("Failed to create nix store directory")?;

        // Copy the pre-built nix store to the shared directory
        tracing::info!(
            "Copying pre-built Nix store from {:?} to {:?}",
            nix_store_source,
            nix_store_dir
        );

        // Copy all contents from the pre-built store
        let output = std::process::Command::new("sh")
            .arg("-c")
            .arg(format!(
                "cp -r --no-dereference --preserve=all {}/* {}",
                nix_store_source.display(),
                nix_store_dir.display()
            ))
            .output()
            .wrap_err("Failed to copy pre-built nix store")?;

        if !output.status.success() {
            return Err(eyre::eyre!(
                "Failed to copy pre-built nix store: cp failed with status {}\nstderr: {}",
                output.status,
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        // Set up the virtiofsd socket
        let virtiofs_socket_path = run_dir.join("virtiofs.sock");

        // Start virtiofsd process
        tracing::info!(
            "Starting virtiofsd with VM rootfs directory: {:?}",
            vm_rootfs_dir
        );
        let virtiofsd_process = Command::new("virtiofsd")
            .args([
                "--socket-path",
                virtiofs_socket_path.to_str().unwrap(),
                "--shared-dir",
                vm_rootfs_dir.to_str().unwrap(),
                "--cache",
                "always",
                "--thread-pool-size",
                "32",
            ])
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .spawn()
            .wrap_err_with(|| "Failed to spawn virtiofsd process")?;

        // Set up the cloud-hypervisor API socket
        let socket_path = run_dir.join("ch-api.sock");

        // Create vsock socket path
        let vsock_socket_path = run_dir.join("vm.sock");

        // Start cloud-hypervisor process
        let process = Command::new("cloud-hypervisor")
            .args(["--api-socket", socket_path.to_str().unwrap()])
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .spawn()
            .wrap_err_with(|| "Failed to spawn cloud-hypervisor process")?;

        // Wait for cloud-hypervisor socket to be created
        while !socket_path.exists() {
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }

        // Wait for virtiofsd socket to be created
        let virtiofs_socket_path_clone = virtiofs_socket_path.clone();
        while !virtiofs_socket_path_clone.exists() {
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        }

        // Create API client
        let mut config = Configuration::new();
        config.base_path = socket_path;
        let client = APIClient::new(config);

        // Allocate IP address for the VM (required for Linux)
        let ip_guard = IpGuard::new(resource_manager.clone())
            .await
            .ok_or_else(|| eyre::eyre!("Failed to allocate IP address for VM {}", id))?;
        let guest_ip = ip_guard
            .ip()
            .ok_or_else(|| eyre::eyre!("IP guard has no IP address"))?;

        tracing::info!("Allocated IP {} for VM {}", guest_ip, id);

        // Allocate CID (Context ID) for vsock communication (required for Linux)
        let cid_guard = CidGuard::new(resource_manager.clone())
            .await
            .ok_or_else(|| eyre::eyre!("Failed to allocate CID for VM {}", id))?;
        let cid = cid_guard
            .cid()
            .ok_or_else(|| eyre::eyre!("CID guard has no CID"))?;

        tracing::debug!("Allocated CID {} for VM {}", cid, id);

        let vsock_config = VsockConfig {
            cid: cid as i64,
            socket: vsock_socket_path.to_str().unwrap().to_string(),
            iommu: Some(false),
            ..Default::default()
        };

        // Configure VM
        let vm_config_ch = VmConfig {
            landlock_enable: Some(false),
            cpus: Some(Box::new(CpusConfig {
                boot_vcpus: vm_config.cpu_count as i32,
                max_vcpus: vm_config.cpu_count as i32,
                ..Default::default()
            })),
            memory: Some(Box::new(MemoryConfig {
                size: (vm_config.memory_size_mb * 1024 * 1024) as i64,
                shared: Some(true),
                hugepages: Some(true),
                hugepage_size: Some(2 * 1024 * 1024), // 2MB hugepages
                ..Default::default()
            })),
            payload: Box::new(PayloadConfig {
                kernel: Some(resources.kernel_path.to_str().unwrap().to_string()),
                initramfs: Some(resources.initrd_path.to_str().unwrap().to_string()),
                cmdline: Some(format!(
                    "console=hvc0 rootfstype=virtiofs root=rootfs ip={}::{}:{}::eth0:off",
                    guest_ip,
                    VM_GATEWAY_IP.to_string(),
                    VM_SUBNET_MASK
                )),
                ..Default::default()
            }),
            fs: Some(vec![FsConfig {
                tag: "rootfs".to_string(),
                socket: virtiofs_socket_path.to_str().unwrap().to_string(),
                num_queues: 1,
                queue_size: 1024,
                ..Default::default()
            }]),
            disks: None, // Using virtiofs instead of disk
            net: Some(vec![NetConfig {
                tap: None, // Let cloud-hypervisor create and manage the TAP device
                ip: Some(VM_GATEWAY_IP.to_string()),
                mask: Some(VM_SUBNET_MASK.to_string()), // /24 subnet
                mac: None,                              // Let cloud-hypervisor generate MAC address
                num_queues: Some(2),
                queue_size: Some(256),
                iommu: Some(false),
                ..Default::default()
            }]),
            console: Some(Box::new(ConsoleConfig {
                mode: Mode::Tty,
                ..Default::default()
            })),
            serial: None,
            vsock: Some(Box::new(vsock_config)),
            ..Default::default()
        };

        tracing::info!("Creating machine {}...", id);

        client
            .default_api()
            .create_vm(vm_config_ch)
            .await
            .map_err(|e| eyre::eyre!("Failed to create VM: {:?}", e))?;

        Ok(Self {
            config: vm_config,
            _resource_guard: Some(resource_guard),
            _ip_guard: Some(ip_guard),
            _cid_guard: Some(cid_guard),
            id,
            _run_dir_temp: run_dir_temp,
            run_dir,
            client,
            process,
            job_config: None,
            virtiofsd_process: Some(virtiofsd_process),
            vm_rootfs_dir,
            job_result: Arc::new(Mutex::new(None)),
            vsock_server_handle: None,
        })
    }

    async fn start(&mut self) -> Result<()> {
        tracing::info!("Starting machine {}...", self.id);

        // Boot the VM
        self.client
            .default_api()
            .boot_vm()
            .await
            .map_err(|e| eyre::eyre!("Failed to boot VM: {:?}", e))?;

        Ok(())
    }

    /// Wait for the cloud-hypervisor process to finish
    async fn wait(&mut self) -> Result<crate::vm::VmExitStatus> {
        let pid = self.process.id();
        tracing::debug!(
            "Starting to wait for cloud-hypervisor process (PID: {})",
            pid
        );

        // Poll until the process exits
        loop {
            // First check if we have a job result (job completed)
            let job_result = self.job_result.lock().await.clone();
            if let Some(success) = job_result {
                tracing::info!(
                    "Job completed with result: {} - initiating VM shutdown",
                    if success { "success" } else { "failure" }
                );

                // Shutdown the VM since the job is complete
                if let Err(e) = self.shutdown().await {
                    tracing::warn!("Failed to shutdown VM after job completion: {}", e);
                }

                // Return the job result
                return Ok(if success {
                    crate::vm::VmExitStatus::Success
                } else {
                    crate::vm::VmExitStatus::Failure
                });
            }

            // Check process status
            match self.process.try_wait() {
                Ok(Some(status)) => {
                    let exit_code = status.code().unwrap_or(1);

                    // Determine exit status: prioritize job result over exit code
                    let exit_status = match job_result {
                        Some(true) => crate::vm::VmExitStatus::Success,
                        Some(false) => crate::vm::VmExitStatus::Failure,
                        None if exit_code == 0 => crate::vm::VmExitStatus::Success,
                        _ => crate::vm::VmExitStatus::Failure,
                    };

                    tracing::info!(
                        "Cloud-hypervisor process (PID: {}) exited with status: {} - job result: {:?}",
                        pid,
                        status,
                        job_result
                    );
                    return Ok(exit_status);
                }
                Ok(None) => {
                    // Process still running, sleep for a bit
                    tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                }
                Err(e) => {
                    return Err(eyre::eyre!(
                        "Failed to wait for cloud-hypervisor process: {}",
                        e
                    ));
                }
            }
        }
    }

    async fn shutdown(&mut self) -> Result<()> {
        tracing::info!("Shutting down VM {}...", self.id);

        // Abort the vsock server task if it's still running
        if let Some(handle) = self.vsock_server_handle.take() {
            tracing::info!("Aborting vsock server task for VM {}", self.id);
            handle.abort();
        }

        // Try to shut down the VM gracefully first through the API
        if let Err(e) = self.client.default_api().shutdown_vm().await {
            tracing::warn!("Failed to shutdown VM via API: {:?}", e);
        }

        // Wait briefly for the VM to respond to the shutdown request
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;

        // Kill the process regardless to ensure cleanup
        if let Err(e) = self.process.kill() {
            tracing::warn!("Failed to kill VM process for job {}: {}", self.id, e);
        }

        // Kill virtiofsd process if it exists
        if let Some(virtiofsd) = &mut self.virtiofsd_process {
            if let Err(e) = virtiofsd.kill() {
                tracing::warn!(
                    "Failed to kill virtiofsd process for job {}: {}",
                    self.id,
                    e
                );
            }
        }

        Ok(())
    }

    fn config(&self) -> &VM {
        &self.config
    }

    fn id(&self) -> &str {
        &self.id
    }

    fn run_dir(&self) -> &PathBuf {
        &self.run_dir
    }

    /// Set job configuration and start vsock server to send it to the guest
    async fn set_job_config(
        &mut self,
        job_config: JobConfig,
        log_sender: tokio::sync::mpsc::Sender<String>,
    ) -> Result<()> {
        // Store job config
        self.job_config = Some(job_config.clone());

        // Get the vsock socket path for the VM
        let vsock_socket_path = self.run_dir.join("vm.sock");

        // Clone the shared job result state for the vsock handler
        let job_result = self.job_result.clone();

        // Run the UNIX socket server in background - it will wait for guest connection
        let handle = tokio::spawn(async move {
            tracing::info!(
                "UNIX socket server task started, waiting for guest connection for job {}",
                job_config.id
            );
            if let Err(e) = vsock::start_unix_config_server(
                vsock_socket_path,
                job_config,
                Some(job_result),
                log_sender,
            )
            .await
            {
                tracing::error!("Failed to run UNIX socket config server: {}", e);
            }
        });

        // Store the handle so we can abort it during shutdown
        self.vsock_server_handle = Some(handle);

        // Give the server a moment to start listening
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;

        Ok(())
    }
}

/// Cleanup VM template directories on startup
pub fn cleanup_vm_template(state_dir: &PathBuf) -> Result<()> {
    let vm_storage_base = state_dir.join("vms");

    if !vm_storage_base.exists() {
        return Ok(());
    }

    tracing::info!(
        "Cleaning up old VM directories in {}",
        vm_storage_base.display()
    );

    // Read all entries in the VM storage directory
    let entries =
        std::fs::read_dir(&vm_storage_base).wrap_err("Failed to read VM storage directory")?;

    for entry in entries {
        let entry = entry.wrap_err("Failed to read directory entry")?;
        let path = entry.path();

        if path.is_dir() {
            tracing::info!("Removing old VM directory: {}", path.display());

            // Make all files and directories writable before removal
            // This is necessary because Nix store files are read-only
            std::process::Command::new("chmod")
                .args(["-R", "u+w"])
                .arg(&path)
                .output()
                .wrap_err("Failed to make VM directory writable")?;

            // Remove the directory
            if let Err(e) = std::fs::remove_dir_all(&path) {
                tracing::warn!("Failed to remove VM directory {}: {}", path.display(), e);
            }
        }
    }

    tracing::info!("VM directory cleanup complete");
    Ok(())
}
