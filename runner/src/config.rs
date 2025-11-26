use std::path::PathBuf;

/// VM runtime configuration
#[derive(Clone)]
pub struct VmConfig {
    /// Path to RESOURCES_DIR containing kernel, initrd, and rootfs
    pub resources_dir: PathBuf,
    /// Path to devenv state directory
    pub state_dir: PathBuf,
}
