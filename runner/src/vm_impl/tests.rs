#[cfg(test)]
mod tests {
    use crate::protocol::{Platform, VM};
    use crate::resource_manager::{ResourceLimits, ResourceManager};
    use crate::vm::create_vm;
    use std::sync::Arc;

    // Helper to create a test VM configuration
    fn test_vm_config(platform: Platform) -> VM {
        VM {
            cpu_count: 2,
            memory_size_mb: 1024, // 1GB
            platform,
        }
    }

    // Helper to create a test resource manager with reasonable limits
    fn test_resource_manager() -> Arc<ResourceManager> {
        let limits = ResourceLimits::new(
            8,                  // 8 CPUs total
            4096 * 1024 * 1024, // 4GB total memory in bytes
            None,               // No instance limit for Linux
        );
        Arc::new(ResourceManager::new(limits))
    }

    #[tokio::test]
    async fn test_spawn_two_vms_sequentially() {
        // Skip test if resources directory not available
        let resources_dir = std::env::var("RESOURCES_DIR").unwrap_or_else(|_| {
            eprintln!("RESOURCES_DIR not set, skipping test");
            String::new()
        });
        if resources_dir.is_empty() || !std::path::Path::new(&resources_dir).exists() {
            eprintln!("RESOURCES_DIR does not exist, skipping test");
            return;
        }

        // Create resource manager
        let resource_manager = test_resource_manager();

        // Create VM configurations for current platform
        let platform = Platform::current();
        let vm_config1 = test_vm_config(platform.clone());
        let vm_config2 = test_vm_config(platform);

        // Spawn first VM (resources allocated internally)
        let vm1_result = create_vm(
            vm_config1.clone(),
            "test-vm-1".to_string(),
            resource_manager.clone(),
        )
        .await;

        assert!(
            vm1_result.is_ok(),
            "Failed to create first VM: {:?}",
            vm1_result.err()
        );
        let vm1 = vm1_result.unwrap();

        // Spawn second VM (resources allocated internally)
        let vm2_result = create_vm(
            vm_config2.clone(),
            "test-vm-2".to_string(),
            resource_manager.clone(),
        )
        .await;

        assert!(
            vm2_result.is_ok(),
            "Failed to create second VM: {:?}",
            vm2_result.err()
        );
        let vm2 = vm2_result.unwrap();

        // Verify resource allocations
        {
            assert_eq!(
                resource_manager.active_job_count().await,
                2,
                "Expected 2 active VMs"
            );

            // Verify the resource summary shows correct usage
            let summary = resource_manager.resource_summary().await;
            assert!(summary.contains("CPUs: 4/8"), "Expected 4 CPUs used");
            assert!(summary.contains("Memory: 2048/4096MB"), "Expected 2GB used");
        }

        // Note: We don't actually start the VMs in this test because that would require
        // real hypervisor resources and proper VM images. This test verifies the
        // resource allocation and VM object creation logic.

        // Clean up by dropping VMs (which releases resources)
        drop(vm1);
        drop(vm2);

        // Wait for async resource release tasks to complete
        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;

        // Verify resources are released
        {
            assert_eq!(
                resource_manager.active_job_count().await,
                0,
                "Expected all VMs to be released"
            );

            // Verify the resource summary shows zero usage
            let summary = resource_manager.resource_summary().await;
            assert!(
                summary.contains("CPUs: 0/8"),
                "Expected all CPUs to be released"
            );
            assert!(
                summary.contains("Memory: 0/4096MB"),
                "Expected all memory to be released"
            );
        }
    }

    #[tokio::test]
    async fn test_resource_exhaustion() {
        // Create resource manager with limited resources
        let limits = ResourceLimits::new(
            2,                  // Only 2 CPUs total (1 available after buffer, not enough for a VM)
            2048 * 1024 * 1024, // 2GB total memory
            None,               // No instance limit
        );
        let resource_manager = Arc::new(ResourceManager::new(limits));

        // VM should fail due to insufficient resources (only 1 CPU available, need 2)
        let platform = Platform::current();
        let vm_config = test_vm_config(platform);

        let vm_result = create_vm(
            vm_config.clone(),
            "test-vm-1".to_string(),
            resource_manager.clone(),
        )
        .await;

        assert!(
            vm_result.is_err(),
            "VM should fail due to insufficient resources"
        );
    }

    #[tokio::test]
    async fn test_concurrent_vm_creation() {
        // Skip if resources directory not available
        let resources_dir = std::env::var("RESOURCES_DIR").unwrap_or_default();
        if resources_dir.is_empty() || !std::path::Path::new(&resources_dir).exists() {
            eprintln!("RESOURCES_DIR does not exist, skipping concurrent test");
            return;
        }

        let resource_manager = test_resource_manager();
        let platform = Platform::current();

        // Spawn multiple VMs concurrently
        let mut handles = vec![];
        for i in 0..3 {
            let rm = resource_manager.clone();
            let vm_config = test_vm_config(platform.clone());
            let handle =
                tokio::spawn(
                    async move { create_vm(vm_config, format!("test-vm-{}", i), rm).await },
                );
            handles.push(handle);
        }

        // Wait for all spawns to complete
        let mut vms = vec![];
        for handle in handles {
            match handle.await {
                Ok(Ok(vm)) => {
                    vms.push(vm);
                }
                Ok(Err(e)) => eprintln!("VM creation failed: {:?}", e),
                Err(e) => panic!("Task panicked: {:?}", e),
            }
        }

        // At least 3 VMs should have been created successfully
        assert!(
            vms.len() >= 3,
            "Expected at least 3 VMs to be created, got {}",
            vms.len()
        );

        // Verify resource usage
        {
            let job_count = resource_manager.active_job_count().await;
            assert_eq!(job_count, vms.len(), "Job count mismatch");

            let summary = resource_manager.resource_summary().await;
            let expected_cpus = vms.len() * 2;
            let expected_memory = vms.len() * 1024;
            assert!(
                summary.contains(&format!("CPUs: {}/8", expected_cpus)),
                "CPU usage mismatch"
            );
            assert!(
                summary.contains(&format!("Memory: {}/4096MB", expected_memory)),
                "Memory usage mismatch"
            );
        }

        // Clean up
        drop(vms);

        // Wait for async resource release tasks to complete
        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;

        // Verify all resources are released
        {
            assert_eq!(
                resource_manager.active_job_count().await,
                0,
                "Expected all VMs to be released"
            );
            let summary = resource_manager.resource_summary().await;
            assert!(
                summary.contains("CPUs: 0/8"),
                "Expected all CPUs to be released"
            );
            assert!(
                summary.contains("Memory: 0/4096MB"),
                "Expected all memory to be released"
            );
        }
    }

    #[tokio::test]
    async fn test_vsock_logging() {
        // Skip test if resources directory not available
        let resources_dir = std::env::var("RESOURCES_DIR").unwrap_or_else(|_| {
            eprintln!("RESOURCES_DIR not set, skipping test");
            String::new()
        });
        if resources_dir.is_empty() || !std::path::Path::new(&resources_dir).exists() {
            eprintln!("RESOURCES_DIR does not exist, skipping test");
            return;
        }

        // Create resource manager
        let resource_manager = test_resource_manager();

        // Create VM configuration for current platform
        let platform = Platform::current();
        let vm_config = test_vm_config(platform);

        // Create VM
        let mut vm = create_vm(
            vm_config,
            "test-vm-logging".to_string(),
            resource_manager.clone(),
        )
        .await
        .expect("Failed to create VM");

        // Create a channel to receive logs
        let (log_sender, mut log_receiver) = tokio::sync::mpsc::channel::<String>(100);

        // Create a test job configuration
        let job_config = crate::protocol::JobConfig {
            id: uuid::Uuid::new_v4(),
            project_url: "https://github.com/octocat/Hello-World".to_string(),
            git_ref: None,
            tasks: vec![],
            cachix_push: false,
            clone_depth: Some(1),
        };

        // Set job configuration with log sender
        vm.set_job_config(job_config.clone(), log_sender.clone())
            .await
            .expect("Failed to set job config");

        // Start the VM
        vm.start().await.expect("Failed to start VM");

        // Collect logs while VM runs
        let mut logs = Vec::new();
        let log_timeout = tokio::time::sleep(tokio::time::Duration::from_secs(30));
        tokio::pin!(log_timeout);

        let mut vm_handle = tokio::spawn(async move {
            let _ = vm.wait().await;
        });

        loop {
            tokio::select! {
                Some(log) = log_receiver.recv() => {
                    println!("Received log: {}", log);
                    logs.push(log);
                }
                _ = &mut log_timeout => {
                    println!("Log collection timeout reached");
                    break;
                }
                _ = &mut vm_handle => {
                    println!("VM exited, waiting for remaining logs...");
                    // Give a bit more time for any pending logs
                    tokio::time::timeout(
                        tokio::time::Duration::from_secs(2),
                        async {
                            while let Some(log) = log_receiver.recv().await {
                                println!("Received log: {}", log);
                                logs.push(log);
                            }
                        }
                    ).await.ok();
                    break;
                }
            }
        }

        // Print summary
        println!("Total logs received: {}", logs.len());

        // Check if we got expected logs
        let has_expected_logs = logs
            .iter()
            .any(|l| l.contains("Received job configuration"));

        assert!(
            has_expected_logs,
            "Did not receive expected log messages via vsock. \
             Received {} logs but none matched expected patterns. \
             The vsock logging infrastructure may not be working correctly.",
            logs.len()
        );
    }
}
