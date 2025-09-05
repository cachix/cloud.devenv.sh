#[cfg(test)]
use crate::protocol::Platform;
use crate::protocol::VM;
use std::collections::{HashMap, VecDeque};
use std::net::Ipv4Addr;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing;
use uuid::Uuid;

/// Reason for rejecting a resource allocation
#[derive(Debug, Clone)]
pub enum RejectionReason {
    InsufficientCPU { required: usize, available: usize },
    InsufficientMemory { required: u64, available: u64 },
    InstanceLimitReached { current: usize, max: usize },
}

impl std::fmt::Display for RejectionReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RejectionReason::InsufficientCPU {
                required,
                available,
            } => {
                write!(
                    f,
                    "Insufficient CPU: required {}, available {}",
                    required, available
                )
            }
            RejectionReason::InsufficientMemory {
                required,
                available,
            } => {
                write!(
                    f,
                    "Insufficient memory: required {}MB, available {}MB",
                    required / (1024 * 1024),
                    available / (1024 * 1024)
                )
            }
            RejectionReason::InstanceLimitReached { current, max } => {
                write!(f, "Instance limit reached: {}/{}", current, max)
            }
        }
    }
}

/// Tracks allocated compute resources
#[derive(Debug)]
struct ResourceState {
    allocated_cpus: usize,
    allocated_memory: u64,
    jobs: HashMap<Uuid, VM>,
}

impl ResourceState {
    fn new() -> Self {
        Self {
            allocated_cpus: 0,
            allocated_memory: 0,
            jobs: HashMap::new(),
        }
    }

    fn total_used_cpus(&self) -> usize {
        self.allocated_cpus
    }

    fn total_used_memory(&self) -> u64 {
        self.allocated_memory
    }

    /// Check if we can allocate resources given the limits
    fn check_limits(
        &self,
        cpus: usize,
        memory_bytes: u64,
        limits: &ResourceLimits,
    ) -> Option<RejectionReason> {
        // Check instance limit first
        if let Some(max_instances) = limits.max_instances {
            let total_instances = self.jobs.len();
            if total_instances >= max_instances {
                return Some(RejectionReason::InstanceLimitReached {
                    current: total_instances,
                    max: max_instances,
                });
            }
        }

        // Keep 1 CPU and 100MB buffer
        let total_used_cpus = self.total_used_cpus();
        let available_cpus = limits.max_cpus.saturating_sub(total_used_cpus + 1);
        if available_cpus < cpus {
            return Some(RejectionReason::InsufficientCPU {
                required: cpus,
                available: available_cpus,
            });
        }

        let total_used_memory = self.total_used_memory();
        let available_memory = limits
            .max_memory_bytes
            .saturating_sub(total_used_memory + (100 * 1024 * 1024));
        if available_memory < memory_bytes {
            return Some(RejectionReason::InsufficientMemory {
                required: memory_bytes,
                available: available_memory,
            });
        }

        None
    }
}

/// Resource limits configuration for the runner
#[derive(Debug, Clone)]
pub struct ResourceLimits {
    pub max_cpus: usize,
    pub max_memory_bytes: u64,
    pub max_instances: Option<usize>,
}

impl ResourceLimits {
    /// Create new resource limits with explicit values
    pub fn new(max_cpus: usize, max_memory_bytes: u64, max_instances: Option<usize>) -> Self {
        Self {
            max_cpus,
            max_memory_bytes,
            max_instances,
        }
    }

    /// Create resource limits with platform-specific defaults
    pub fn with_platform_defaults() -> Self {
        let sys = sysinfo::System::new_all();
        let max_cpus = sys.cpus().len();
        let max_memory_bytes = sys.total_memory();

        // TODO(sander): change to 2 instances once supported
        #[cfg(target_os = "macos")]
        let max_instances = Some(1);
        #[cfg(not(target_os = "macos"))]
        let max_instances = None;

        Self {
            max_cpus,
            max_memory_bytes,
            max_instances,
        }
    }

    /// Create resource limits from existing values with platform-specific instance limits
    pub fn from_system_resources(max_cpus: usize, max_memory_bytes: u64) -> Self {
        // TODO(sander): change to 2 instances once supported
        #[cfg(target_os = "macos")]
        let max_instances = Some(1);
        #[cfg(not(target_os = "macos"))]
        let max_instances = None;

        Self {
            max_cpus,
            max_memory_bytes,
            max_instances,
        }
    }
}

/// Manages VM resource allocation and tracking
pub struct ResourceManager {
    pub limits: ResourceLimits,
    // Allocated resources
    allocation: Arc<RwLock<ResourceState>>,
    // IP pool - queue of available IPs
    free_ips: Arc<RwLock<VecDeque<Ipv4Addr>>>,
}

impl ResourceManager {
    /// Create a new ResourceManager with explicit resource limits
    pub fn new(limits: ResourceLimits) -> Self {
        // Initialize IP pool with a range of IPs (10.0.0.2 - 10.0.0.254)
        // Reserve 10.0.0.1 for the host/gateway
        let mut free_ips = VecDeque::new();
        for i in 2..=254 {
            free_ips.push_back(Ipv4Addr::new(10, 0, 0, i));
        }

        Self {
            limits,
            allocation: Arc::new(RwLock::new(ResourceState::new())),
            free_ips: Arc::new(RwLock::new(free_ips)),
        }
    }

    /// Create a ResourceManager with platform-specific defaults
    pub fn with_platform_defaults() -> Self {
        Self::new(ResourceLimits::with_platform_defaults())
    }

    /// Create a ResourceManager from system resources with platform-specific limits
    pub fn from_system_resources(max_cpus: usize, max_memory_bytes: u64) -> Self {
        Self::new(ResourceLimits::from_system_resources(
            max_cpus,
            max_memory_bytes,
        ))
    }

    /// Allocate resources for a job atomically, returning a guard that releases on drop
    pub async fn allocate_resources(
        self: &Arc<Self>,
        job_id: Uuid,
        vm: VM,
    ) -> Result<ResourceGuard, RejectionReason> {
        let memory_bytes = vm.memory_size_mb * 1024 * 1024;

        // Single lock acquisition for atomic allocation
        let mut allocation = self.allocation.write().await;

        if let Some(reason) = allocation.check_limits(vm.cpu_count, memory_bytes, &self.limits) {
            return Err(reason);
        }

        // Allocate resources
        allocation.allocated_cpus += vm.cpu_count;
        allocation.allocated_memory += memory_bytes;
        allocation.jobs.insert(job_id, vm.clone());

        tracing::debug!(
            "Allocated resources for job {}: {} CPUs, {}MB RAM (total allocated: {} CPUs, {}MB RAM)",
            job_id,
            vm.cpu_count,
            vm.memory_size_mb,
            allocation.allocated_cpus,
            allocation.allocated_memory / (1024 * 1024)
        );

        Ok(ResourceGuard::new(job_id, vm, self.clone()))
    }

    /// Check if we can allocate resources for a job
    pub async fn can_allocate(&self, cpu_count: usize, memory_mb: u64) -> bool {
        let memory_bytes = memory_mb * 1024 * 1024;
        let allocation = self.allocation.read().await;
        allocation
            .check_limits(cpu_count, memory_bytes, &self.limits)
            .is_none()
    }

    /// Release resources for a job
    pub async fn release_job(&self, job_id: Uuid) -> Option<VM> {
        let mut allocation = self.allocation.write().await;
        let vm = allocation.jobs.remove(&job_id)?;

        let memory_bytes = vm.memory_size_mb * 1024 * 1024;

        // Update counters
        allocation.allocated_cpus = allocation.allocated_cpus.saturating_sub(vm.cpu_count);
        allocation.allocated_memory = allocation.allocated_memory.saturating_sub(memory_bytes);

        tracing::debug!(
            "Released resources for job {}: {} CPUs, {}MB RAM (total used: {} CPUs, {}MB RAM)",
            job_id,
            vm.cpu_count,
            vm.memory_size_mb,
            allocation.allocated_cpus,
            allocation.allocated_memory / (1024 * 1024)
        );

        Some(vm)
    }

    /// Get current resource usage summary
    pub async fn resource_summary(&self) -> String {
        let allocation = self.allocation.read().await;
        let total_cpus = allocation.total_used_cpus();
        let total_memory = allocation.total_used_memory();
        let job_count = allocation.jobs.len();

        let instance_info = if let Some(max_instances) = self.limits.max_instances {
            format!(", Instances: {job_count}/{max_instances}")
        } else {
            format!(", Active Jobs: {job_count}")
        };

        format!(
            "CPUs: {}/{} ({}% used), Memory: {}/{}MB ({}% used){}",
            total_cpus,
            self.limits.max_cpus,
            (total_cpus as f64 / self.limits.max_cpus as f64 * 100.0) as usize,
            total_memory / (1024 * 1024),
            self.limits.max_memory_bytes / (1024 * 1024),
            (total_memory as f64 / self.limits.max_memory_bytes as f64 * 100.0) as usize,
            instance_info
        )
    }

    /// Check if we have minimal capacity (for at least 1 CPU)
    pub async fn has_minimal_capacity(&self) -> bool {
        self.can_allocate(1, 0).await
    }

    /// Check if a job is currently registered
    pub async fn is_job_registered(&self, job_id: &Uuid) -> bool {
        let allocation = self.allocation.read().await;
        allocation.jobs.contains_key(job_id)
    }

    /// Get VM configuration for a job
    pub async fn get_job_vm_config(&self, job_id: &Uuid) -> Option<VM> {
        let allocation = self.allocation.read().await;
        allocation.jobs.get(job_id).cloned()
    }

    /// Get total number of active jobs
    pub async fn active_job_count(&self) -> usize {
        let allocation = self.allocation.read().await;
        allocation.jobs.len()
    }

    /// Get current resource usage statistics
    pub async fn get_usage_stats(&self) -> (usize, u64) {
        let allocation = self.allocation.read().await;
        (
            allocation.allocated_cpus,
            allocation.allocated_memory / (1024 * 1024),
        )
    }

    /// Allocate an IP address from the pool
    pub async fn allocate_ip(&self) -> Option<Ipv4Addr> {
        let mut free_ips = self.free_ips.write().await;
        let ip = free_ips.pop_front();

        if let Some(ip) = ip {
            tracing::debug!(
                "Allocated IP address: {} ({} IPs remaining)",
                ip,
                free_ips.len()
            );
        } else {
            tracing::warn!("No available IP addresses in pool");
        }

        ip
    }

    /// Release an IP address back to the pool
    pub async fn release_ip(&self, ip: Ipv4Addr) {
        let mut free_ips = self.free_ips.write().await;
        free_ips.push_back(ip);
        tracing::debug!(
            "Released IP address: {} ({} IPs available)",
            ip,
            free_ips.len()
        );
    }
}

/// RAII guard for IP address allocation
/// Automatically releases the IP address when dropped
pub struct IpGuard {
    ip: Option<Ipv4Addr>,
    resource_manager: Arc<ResourceManager>,
}

impl IpGuard {
    /// Create a new IP guard by allocating an IP from the resource manager
    pub async fn new(resource_manager: Arc<ResourceManager>) -> Option<Self> {
        let ip = resource_manager.allocate_ip().await?;
        Some(Self {
            ip: Some(ip),
            resource_manager,
        })
    }

    /// Get the allocated IP address
    pub fn ip(&self) -> Option<Ipv4Addr> {
        self.ip
    }

    /// Take the IP address, preventing automatic release on drop
    pub fn take(mut self) -> Option<Ipv4Addr> {
        self.ip.take()
    }
}

impl Drop for IpGuard {
    fn drop(&mut self) {
        if let Some(ip) = self.ip {
            // We need to spawn a task to release the IP since drop is not async
            let resource_manager = self.resource_manager.clone();
            tokio::spawn(async move {
                resource_manager.release_ip(ip).await;
            });
        }
    }
}

/// RAII guard for allocated resources
/// Automatically releases resources when dropped
pub struct ResourceGuard {
    job_id: Option<Uuid>,
    vm: Option<VM>,
    resource_manager: Arc<ResourceManager>,
}

impl ResourceGuard {
    /// Create a new resource guard
    fn new(job_id: Uuid, vm: VM, resource_manager: Arc<ResourceManager>) -> Self {
        Self {
            job_id: Some(job_id),
            vm: Some(vm),
            resource_manager,
        }
    }

    /// Get the job ID
    pub fn job_id(&self) -> Option<Uuid> {
        self.job_id
    }

    /// Get the VM configuration
    pub fn vm(&self) -> Option<&VM> {
        self.vm.as_ref()
    }

    /// Take the job ID and VM, preventing automatic release on drop
    pub fn take(mut self) -> Option<(Uuid, VM)> {
        match (self.job_id.take(), self.vm.take()) {
            (Some(id), Some(vm)) => Some((id, vm)),
            _ => None,
        }
    }
}

impl Drop for ResourceGuard {
    fn drop(&mut self) {
        if let Some(job_id) = self.job_id {
            // We need to spawn a task to release since drop is not async
            let resource_manager = self.resource_manager.clone();
            tokio::spawn(async move {
                resource_manager.release_job(job_id).await;
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures_util::future;

    #[tokio::test]
    async fn test_basic_allocation() {
        let limits = ResourceLimits::new(4, 1024 * 1024 * 1024, None);
        let manager = Arc::new(ResourceManager::new(limits));

        // Allocate resources
        let job_id = Uuid::now_v7();
        let vm = VM {
            cpu_count: 2,
            memory_size_mb: 512,
            platform: Platform::X86_64Linux,
        };
        let guard = manager
            .allocate_resources(job_id, vm.clone())
            .await
            .unwrap();

        // Verify guard has correct values
        assert_eq!(guard.job_id(), Some(job_id));
        assert_eq!(guard.vm().map(|v| v.cpu_count), Some(2));
        assert_eq!(guard.vm().map(|v| v.memory_size_mb), Some(512));

        // Verify VM is registered
        assert!(manager.is_job_registered(&job_id).await);
        assert_eq!(manager.active_job_count().await, 1);

        // Drop guard to release
        drop(guard);
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;

        // Verify resources released
        assert!(!manager.is_job_registered(&job_id).await);
        assert_eq!(manager.active_job_count().await, 0);
    }

    #[tokio::test]
    async fn test_cpu_limits_with_buffer() {
        let limits = ResourceLimits::new(4, 1024 * 1024 * 1024, None);
        let manager = Arc::new(ResourceManager::new(limits));

        // Should succeed - uses 3 CPUs, leaves 1 CPU buffer
        let job_id = Uuid::new_v4();
        let vm = VM {
            cpu_count: 3,
            memory_size_mb: 100,
            platform: Platform::X86_64Linux,
        };
        let guard = manager.allocate_resources(job_id, vm).await.unwrap();

        // Should fail - would use all 4 CPUs, no buffer
        let job_id2 = Uuid::now_v7();
        let vm2 = VM {
            cpu_count: 1,
            memory_size_mb: 100,
            platform: Platform::X86_64Linux,
        };
        let result = manager.allocate_resources(job_id2, vm2).await;
        assert!(matches!(
            result,
            Err(RejectionReason::InsufficientCPU { .. })
        ));

        drop(guard);
    }

    #[tokio::test]
    async fn test_memory_limits_with_buffer() {
        let limits = ResourceLimits::new(8, 200 * 1024 * 1024, None); // 200MB total
        let manager = Arc::new(ResourceManager::new(limits));

        // Should succeed - uses 100MB, leaves 100MB buffer
        let job_id = Uuid::new_v4();
        let vm = VM {
            cpu_count: 1,
            memory_size_mb: 100,
            platform: Platform::X86_64Linux,
        };
        let guard = manager.allocate_resources(job_id, vm).await.unwrap();

        // Should fail - would leave less than 100MB buffer
        let job_id2 = Uuid::new_v4();
        let vm2 = VM {
            cpu_count: 1,
            memory_size_mb: 1,
            platform: Platform::X86_64Linux,
        };
        let result = manager.allocate_resources(job_id2, vm2).await;
        assert!(matches!(
            result,
            Err(RejectionReason::InsufficientMemory { .. })
        ));

        drop(guard);
    }

    #[tokio::test]
    async fn test_instance_limits() {
        let limits = ResourceLimits::new(8, 8 * 1024 * 1024 * 1024, Some(2));
        let manager = Arc::new(ResourceManager::new(limits));

        // Allocate first instance
        let job_id1 = Uuid::now_v7();
        let vm1 = VM {
            cpu_count: 1,
            memory_size_mb: 100,
            platform: Platform::X86_64Linux,
        };
        let _guard1 = manager.allocate_resources(job_id1, vm1).await.unwrap();

        // Allocate second instance
        let job_id2 = Uuid::new_v4();
        let vm2 = VM {
            cpu_count: 1,
            memory_size_mb: 100,
            platform: Platform::X86_64Linux,
        };
        let _guard2 = manager.allocate_resources(job_id2, vm2).await.unwrap();

        // Third instance should fail
        let job_id3 = Uuid::now_v7();
        let vm3 = VM {
            cpu_count: 1,
            memory_size_mb: 100,
            platform: Platform::X86_64Linux,
        };
        let result = manager.allocate_resources(job_id3, vm3).await;
        assert!(matches!(
            result,
            Err(RejectionReason::InstanceLimitReached { .. })
        ));
    }

    #[tokio::test]
    async fn test_concurrent_allocations() {
        let limits = ResourceLimits::new(4, 1024 * 1024 * 1024, None);
        let manager = Arc::new(ResourceManager::new(limits));

        // Create multiple concurrent allocations
        let mut handles = vec![];
        for _ in 0..4 {
            let manager_clone = manager.clone();
            let job_id = Uuid::now_v7();
            let vm = VM {
                cpu_count: 1,
                memory_size_mb: 100,
                platform: Platform::X86_64Linux,
            };
            let handle =
                tokio::spawn(async move { manager_clone.allocate_resources(job_id, vm).await });
            handles.push(handle);
        }

        let results = future::join_all(handles).await;

        // Exactly 3 should succeed (4 CPUs - 1 buffer)
        let successes = results
            .iter()
            .filter(|r| r.as_ref().map(|res| res.is_ok()).unwrap_or(false))
            .count();
        assert_eq!(successes, 3);
    }

    #[tokio::test]
    async fn test_ip_guard_lifecycle() {
        let limits = ResourceLimits::new(4, 1024 * 1024 * 1024, None);
        let manager = Arc::new(ResourceManager::new(limits));

        // Allocate IP
        let ip_guard = IpGuard::new(manager.clone()).await.unwrap();
        let ip = ip_guard.ip().unwrap();
        assert_eq!(ip.octets()[0], 10);
        assert_eq!(ip.octets()[1], 0);
        assert_eq!(ip.octets()[2], 0);
        assert!(ip.octets()[3] >= 2 && ip.octets()[3] <= 254);

        // Drop guard to release
        drop(ip_guard);
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;

        // Should be able to allocate again
        let ip_guard2 = IpGuard::new(manager.clone()).await.unwrap();
        assert!(ip_guard2.ip().is_some());
    }

    #[tokio::test]
    async fn test_ip_pool_exhaustion() {
        let limits = ResourceLimits::new(4, 1024 * 1024 * 1024, None);
        let manager = Arc::new(ResourceManager::new(limits));

        // Allocate all IPs
        let mut guards = vec![];
        for _ in 0..253 {
            if let Some(guard) = IpGuard::new(manager.clone()).await {
                guards.push(guard);
            }
        }
        assert_eq!(guards.len(), 253);

        // Next allocation should fail
        let result = IpGuard::new(manager.clone()).await;
        assert!(result.is_none());

        // Release one
        guards.pop();
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;

        // Should be able to allocate again
        let guard = IpGuard::new(manager.clone()).await;
        assert!(guard.is_some());
    }

    #[tokio::test]
    async fn test_resource_guard_explicit_drop() {
        let limits = ResourceLimits::new(4, 1024 * 1024 * 1024, None);
        let manager = Arc::new(ResourceManager::new(limits));

        // Allocate resources
        let job_id = Uuid::new_v4();
        let vm = VM {
            cpu_count: 2,
            memory_size_mb: 512,
            platform: Platform::X86_64Linux,
        };
        let guard = manager
            .allocate_resources(job_id, vm.clone())
            .await
            .unwrap();

        // Explicitly drop the guard
        drop(guard);

        // Wait a bit for the async drop to complete
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;

        // Should be able to allocate same resources again immediately
        let job_id2 = Uuid::new_v4();
        let guard2 = manager.allocate_resources(job_id2, vm).await.unwrap();
        assert!(guard2.job_id().is_some());
    }

    #[tokio::test]
    async fn test_allocation_with_excessive_resources() {
        let limits = ResourceLimits::new(4, 1024 * 1024 * 1024, None);
        let manager = Arc::new(ResourceManager::new(limits));

        // First allocation uses 2 CPUs
        let job_id1 = Uuid::new_v4();
        let vm1 = VM {
            cpu_count: 2,
            memory_size_mb: 512,
            platform: Platform::X86_64Linux,
        };
        let _guard1 = manager.allocate_resources(job_id1, vm1).await.unwrap();

        // Try to allocate 3 more CPUs (would exceed limit with buffer)
        let job_id2 = Uuid::new_v4();
        let vm2 = VM {
            cpu_count: 3,
            memory_size_mb: 512,
            platform: Platform::X86_64Linux,
        };

        let result = manager.allocate_resources(job_id2, vm2).await;
        assert!(matches!(
            result,
            Err(RejectionReason::InsufficientCPU { .. })
        ));
    }

    #[tokio::test]
    async fn test_resource_summary() {
        let limits = ResourceLimits::new(4, 1024 * 1024 * 1024, Some(2));
        let manager = Arc::new(ResourceManager::new(limits));

        // Initial state
        let summary = manager.resource_summary().await;
        assert!(summary.contains("CPUs: 0/4"));
        assert!(summary.contains("Memory: 0/1024MB"));
        assert!(summary.contains("Instances: 0/2"));

        // With allocation
        let job_id = Uuid::new_v4();
        let vm = VM {
            cpu_count: 2,
            memory_size_mb: 512,
            platform: Platform::X86_64Linux,
        };
        let _guard = manager.allocate_resources(job_id, vm).await.unwrap();

        let summary = manager.resource_summary().await;
        assert!(summary.contains("CPUs: 2/4"));
        assert!(summary.contains("Memory: 512/1024MB"));
        assert!(summary.contains("Instances: 1/2"));
    }

    #[tokio::test]
    async fn test_resource_guard_take_prevents_release() {
        let limits = ResourceLimits::new(4, 1024 * 1024 * 1024, None);
        let manager = Arc::new(ResourceManager::new(limits));

        // Allocate resources
        let job_id = Uuid::new_v4();
        let vm = VM {
            cpu_count: 2,
            memory_size_mb: 512,
            platform: Platform::X86_64Linux,
        };
        let guard = manager
            .allocate_resources(job_id, vm.clone())
            .await
            .unwrap();

        // Verify job is registered
        assert_eq!(guard.job_id(), Some(job_id));

        // Take the job_id and vm
        let taken = guard.take();
        assert_eq!(taken.unwrap().0, job_id);

        // guard has been consumed by take(), no need to drop
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;

        // Job should still be registered
        assert!(manager.is_job_registered(&job_id).await);

        // Manually release
        manager.release_job(job_id).await;
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
        assert!(!manager.is_job_registered(&job_id).await);
    }

    #[tokio::test]
    async fn test_ip_guard_take_prevents_release() {
        let limits = ResourceLimits::new(4, 1024 * 1024 * 1024, None);
        let manager = Arc::new(ResourceManager::new(limits));

        let ip_guard = IpGuard::new(manager.clone()).await.unwrap();

        // Count available IPs before taking
        let available_before = {
            let free_ips = manager.free_ips.read().await;
            free_ips.len()
        };

        let ip = ip_guard.take().unwrap();

        // ip_guard has been consumed by take(), no need to drop
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;

        // Count should be the same
        let available_after = {
            let free_ips = manager.free_ips.read().await;
            free_ips.len()
        };
        assert_eq!(available_before, available_after);

        // Manually release
        manager.release_ip(ip).await;
    }
}
