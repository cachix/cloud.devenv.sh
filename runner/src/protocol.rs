use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub enum Platform {
    #[serde(rename = "x86_64-linux")]
    X86_64Linux,
    #[serde(rename = "aarch64-darwin")]
    AArch64Darwin,
}

impl Platform {
    /// Returns the platform for the current operating system
    pub fn current() -> Self {
        if cfg!(target_os = "linux") {
            Platform::X86_64Linux
        } else if cfg!(target_os = "macos") {
            Platform::AArch64Darwin
        } else {
            panic!("Unsupported platform for VM")
        }
    }
}

impl std::fmt::Display for Platform {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Platform::X86_64Linux => write!(f, "x86_64-linux"),
            Platform::AArch64Darwin => write!(f, "aarch64-darwin"),
        }
    }
}

// This allows us to parse a platform string
impl std::str::FromStr for Platform {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "x86_64-linux" => Ok(Platform::X86_64Linux),
            "aarch64-darwin" => Ok(Platform::AArch64Darwin),
            _ => Err(format!("Unknown platform: {s}")),
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct VM {
    pub cpu_count: usize,
    pub memory_size_mb: u64,
    pub platform: Platform,
}

/// Configuration for a job to be run in a VM
/// This is sent over the vsock connection to the guest
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct JobConfig {
    /// The unique identifier for this job
    pub id: uuid::Uuid,
    /// URL of the Git repository to clone
    pub project_url: String,
    /// Git reference (branch, tag, or commit SHA) to check out
    pub git_ref: Option<String>,
    /// Tasks to run after setup
    pub tasks: Vec<String>,
    /// Whether to push to Cachix
    pub cachix_push: bool,
    /// Clone depth (shallow clone)
    pub clone_depth: Option<u32>,
}

/// Port numbers for the vsock protocol
pub const CONFIG_VSOCK_PORT: u32 = 1234;

/// Message sent from the host to the guest over vsock
#[derive(Debug, Serialize, Deserialize)]
pub enum VsockHostMessage {
    /// Job configuration
    JobConfig(JobConfig),
}

/// Message sent from the guest to the host over vsock
#[derive(Debug, Serialize, Deserialize)]
pub enum VsockGuestMessage {
    /// Guest is ready to execute job
    Ready { id: uuid::Uuid },
    /// Job execution completed
    Complete { id: uuid::Uuid, success: bool },
    /// Log message from guest
    Log {
        id: uuid::Uuid,
        level: String,
        target: String,
        message: String,
        fields: std::collections::HashMap<String, String>,
    },
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub enum ServerMessage {
    NewJobAvailable {
        id: uuid::Uuid,
        vm: VM,
    },
    JobClaimed {
        id: uuid::Uuid,
        vm: VM,
        log_url: url::Url,
    },
    JobTimedOut {
        id: uuid::Uuid,
    },
    // We can use JobCancelled for user-initiated cancellations, which is clearer
    // than reusing JobTimedOut that's for timeout-based cancellations
    JobCancelled {
        id: uuid::Uuid,
    },
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RunnerMetrics {
    pub platform: Platform,
    pub cpu_count: usize,
    pub memory_size_mb: u64,
    pub used_cpu_count: usize,
    pub used_memory_mb: u64,
    pub cpu_utilization_percent: f32,
    pub memory_utilization_percent: f32,
    pub active_jobs: usize,
    pub queued_jobs: usize,
    pub running_jobs: usize,
    pub max_instances: Option<usize>,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum ClientMessage {
    ClaimJob { id: uuid::Uuid, vm: VM },
    UpdateJobStatus { id: uuid::Uuid, status: JobStatus },
    RequestJob,
    ReportMetrics(RunnerMetrics),
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, ToSchema)]
pub enum CompletionStatus {
    Failed,
    Success,
    Cancelled,
    TimedOut,
    Skipped,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, ToSchema)]
pub enum JobStatus {
    Queued,
    Running,
    Complete(CompletionStatus),
}
