use crate::runner::model::Platform;
use devenv_runner::protocol::{Platform as RunnerPlatform, VM};
use serde::Deserialize;

/// A collection of VM configurations parsed from a devenv.yaml file.
#[derive(Debug)]
pub struct FinalCloud(Vec<VM>);

impl FinalCloud {
    /// Create a new `FinalCloud` from a devenv.yaml string.
    ///
    /// This parses the YAML string to extract platform configurations with
    /// memory and CPU settings. If the string is empty or doesn't contain platform
    /// definitions, default platforms (x86_64-linux and aarch64-darwin) are used.
    ///
    /// # Arguments
    /// * `devenv_config_str` - A string containing YAML configuration, can be empty
    ///
    /// # Returns
    /// * `Result<FinalCloud, String>` - The VM configurations or an error message
    ///
    /// # Example
    /// ```
    /// use devenv_backend::runner::cloudconfig::FinalCloud;
    ///
    /// let yaml = r#"
    /// cloud:
    ///   memory: 4gb
    ///   cpus: 2
    ///   platforms:
    ///     - x86_64-linux
    ///     - name: aarch64-darwin
    ///       memory: 8gb
    /// "#;
    /// let vm_configs = FinalCloud::new(yaml).unwrap();
    ///
    /// // Or use default configuration with empty string
    /// let default_configs = FinalCloud::new("").unwrap();
    /// ```
    pub fn new(devenv_config_str: &str) -> Result<Self, String> {
        // If the string is empty, use an empty YAML document to get defaults
        let yaml_str = if devenv_config_str.trim().is_empty() {
            "{}"
        } else {
            devenv_config_str
        };

        let config: Config =
            serde_yaml::from_str(yaml_str).map_err(|e| format!("Failed to parse YAML: {}", e))?;

        // Constants for default values
        const DEFAULT_MEMORY: &str = "4gb";
        const DEFAULT_CPUS: u32 = 2;

        // Resolve cloud-level settings with defaults
        let cloud = &config.cloud;
        let cloud_memory_str = cloud.memory.as_deref().unwrap_or(DEFAULT_MEMORY);
        let cloud_memory_mb = parse_memory(cloud_memory_str)?;
        let cloud_cpus = cloud.cpus.unwrap_or(DEFAULT_CPUS);

        // If no platforms provided, default to the two allowed ones.
        let platforms_raw = cloud.platforms.as_ref().map_or_else(
            || {
                vec![
                    PlatformConfig::Simple("x86_64-linux".to_string()),
                    PlatformConfig::Simple("aarch64-darwin".to_string()),
                ]
            },
            |p| p.clone(),
        );

        // Process each platform configuration
        let vms = platforms_raw.into_iter()
            .map(|platform_config| {
                let (name, memory_opt, cpus_opt) = match platform_config {
                    PlatformConfig::Simple(name) => (name, None, None),
                    PlatformConfig::Detailed { name, memory, cpus } => (name, memory, cpus),
                };

                // Validate platform name and convert to enum
                let platform = match name.as_str() {
                    "x86_64-linux" => Platform::X86_64Linux,
                    "aarch64-darwin" => Platform::AArch64Darwin,
                    _ => return Err(format!(
                        "Platform '{}' is not supported. Only 'x86_64-linux' and 'aarch64-darwin' are allowed",
                        name
                    )),
                };

                // Get platform memory, using platform override or cloud default
                let memory_mb = if let Some(mem_str) = memory_opt {
                    parse_memory(&mem_str)?
                } else {
                    cloud_memory_mb
                };

                // Get platform CPUs, using platform override or cloud default
                let cpus = cpus_opt.unwrap_or(cloud_cpus);

                // Convert directly to VM struct
                Ok(VM {
                    cpu_count: cpus as usize,
                    memory_size_mb: memory_mb as u64,
                    platform: match platform {
                        Platform::X86_64Linux => RunnerPlatform::X86_64Linux,
                        Platform::AArch64Darwin => RunnerPlatform::AArch64Darwin,
                    },
                })
            })
            .collect::<Result<Vec<VM>, String>>()?;

        Ok(FinalCloud(vms))
    }

    /// Returns the VMs contained in this FinalCloud
    pub fn vms(&self) -> &[VM] {
        &self.0
    }

    /// Converts FinalCloud into a Vec<VM>
    pub fn into_vms(self) -> Vec<VM> {
        self.0
    }
}

// Private implementation details below

/// Top-level configuration structure for cloud configuration.
#[derive(Debug, Deserialize)]
struct Config {
    /// The cloud-specific configuration
    #[serde(default)]
    cloud: Cloud,
}

/// Cloud configuration containing memory, CPU, and platform settings.
#[derive(Debug, Deserialize, Default)]
struct Cloud {
    /// Default memory for all platforms (e.g., "4gb" or "512mb")
    #[serde(default)]
    memory: Option<String>,

    /// Default CPU count for all platforms
    #[serde(default)]
    cpus: Option<u32>,

    /// List of platform configurations
    #[serde(default)]
    platforms: Option<Vec<PlatformConfig>>,
}

/// Configuration for a platform in the cloud configuration.
///
/// This enum allows two ways to specify a platform:
/// - A simple string name (e.g., "x86_64-linux")
/// - A detailed object with name and optional overrides for memory and cpus
#[derive(Debug, Deserialize, Clone)]
#[serde(untagged)]
enum PlatformConfig {
    /// A simple platform is represented as just a name.
    Simple(String),

    /// A detailed platform configuration with optional overrides.
    Detailed {
        /// The platform name (e.g., "x86_64-linux" or "aarch64-darwin")
        name: String,

        /// Optional memory specification (e.g., "4gb" or "512mb")
        #[serde(default)]
        memory: Option<String>,

        /// Optional CPU count
        #[serde(default)]
        cpus: Option<u32>,
    },
}

/// Parses a memory string into megabytes.
///
/// The string must end with either "mb" or "gb" (case-insensitive),
/// and 1 GB is interpreted as 1024 MB.
fn parse_memory(s: &str) -> Result<u32, String> {
    let s = s.trim().to_lowercase();

    if s.ends_with("gb") {
        let num_str = s.trim_end_matches("gb").trim();
        let num: u32 = num_str
            .parse()
            .map_err(|_| format!("Invalid memory size: {}", s))?;
        Ok(num * 1024)
    } else if s.ends_with("mb") {
        let num_str = s.trim_end_matches("mb").trim();
        let num: u32 = num_str
            .parse()
            .map_err(|_| format!("Invalid memory size: {}", s))?;
        Ok(num)
    } else {
        Err(format!("Memory size must end with 'mb' or 'gb': {}", s))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use devenv_runner::protocol::Platform as RunnerPlatform;

    #[test]
    fn test_final_cloud_from_yaml() {
        let yaml_str = r#"
cloud:
  memory: 200mb
  cpus: 2
  platforms:
    - name: x86_64-linux
      memory: 150mb
    - aarch64-darwin
        "#;

        let cloud = FinalCloud::new(yaml_str).expect("Failed to create VM configs");
        let vms = cloud.vms();

        assert_eq!(vms.len(), 2);

        // Verify the first VM: x86_64-linux with custom memory "150mb" (150 MB) and inherited cpus=2
        let vm1 = &vms[0];
        assert!(matches!(vm1.platform, RunnerPlatform::X86_64Linux));
        assert_eq!(vm1.memory_size_mb, 150);
        assert_eq!(vm1.cpu_count, 2);

        // Verify the second VM: aarch64-darwin inherits cloud memory ("200mb") and cpus
        let vm2 = &vms[1];
        assert!(matches!(vm2.platform, RunnerPlatform::AArch64Darwin));
        assert_eq!(vm2.memory_size_mb, 200);
        assert_eq!(vm2.cpu_count, 2);
    }

    #[test]
    fn test_final_cloud_default() {
        // YAML with no cloud section provided.
        let yaml_str = r#"
# No cloud key provided
        "#;

        let cloud = FinalCloud::new(yaml_str).expect("Failed to create VM configs");
        let vms = cloud.vms();

        // Verify we get the default platforms: x86_64-linux and aarch64-darwin
        assert_eq!(vms.len(), 2);

        // Verify first default VM with default memory (4GB) and CPUs (2)
        let vm1 = &vms[0];
        assert!(matches!(vm1.platform, RunnerPlatform::X86_64Linux));
        assert_eq!(vm1.memory_size_mb, 4096);
        assert_eq!(vm1.cpu_count, 2);

        // Verify second default VM with default memory (4GB) and CPUs (2)
        let vm2 = &vms[1];
        assert!(matches!(vm2.platform, RunnerPlatform::AArch64Darwin));
        assert_eq!(vm2.memory_size_mb, 4096);
        assert_eq!(vm2.cpu_count, 2);
    }

    #[test]
    fn test_final_cloud_reject_custom_platform() {
        // YAML containing a custom platform name (not allowed).
        let yaml_str = r#"
cloud:
  memory: 4gb
  cpus: 2
  platforms:
    - name: custom-platform
      memory: 2gb
        "#;

        let result = FinalCloud::new(yaml_str);
        assert!(result.is_err());
        if let Err(e) = result {
            assert!(e.contains("Platform '"));
        }
    }
}
