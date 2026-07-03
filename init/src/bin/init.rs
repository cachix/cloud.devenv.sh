#![cfg_attr(target_os = "linux", doc = "Linux init system implementation")]

#[cfg(target_os = "linux")]
mod linux {
    use clap::Parser;
    use color_eyre::eyre::Result;
    use devenv_init::{
        mount_essential_filesystems, mount_root_filesystem, mount_store_overlay,
        pivot_to_devenv_root, set_hostname, NEW_ROOT,
    };
    use tracing::{error, info};
    use tracing_subscriber::prelude::*;

    /// The init system for devenv.sh that launches cloud-hypervisor
    #[derive(Parser, Debug)]
    #[command(version, about)]
    struct Args {}

    #[tokio::main]
    pub async fn main() -> Result<()> {
        // Set up logging (this will output to console/serial)
        color_eyre::install()?;
        tracing_subscriber::registry()
            .with(tracing_subscriber::fmt::layer())
            .init();

        info!("Starting devenv-init");

        // Create essential directories if they don't exist
        let essential_dirs = [
            "/proc", "/sys", "/dev", "/tmp", "/run", NEW_ROOT, "/dev/pts", "/dev/shm",
        ];

        for dir in essential_dirs {
            if let Err(e) = std::fs::create_dir_all(dir) {
                tracing::warn!("Failed to create directory {}: {}", dir, e);
            }
        }

        // Mount essential virtual filesystems needed for operation
        mount_essential_filesystems()?;

        // Set up /dev/pts and other virtual filesystems
        let additional_mounts = [
            devenv_init::MountPoint {
                device: "devpts",
                mount_path: "/dev/pts",
                fs_type: "devpts",
                options: &["mode=0620,gid=5"],
            },
            devenv_init::MountPoint {
                device: "tmpfs",
                mount_path: "/dev/shm",
                fs_type: "tmpfs",
                options: &["mode=1777", "size=128M"],
            },
        ];

        for mount in &additional_mounts {
            devenv_init::mount_filesystem(
                mount.device,
                mount.mount_path,
                mount.fs_type,
                mount.options,
            )?;
        }

        info!("Mounting root filesystem with /mnt");
        if let Err(e) = mount_root_filesystem() {
            error!("Failed to mount root filesystem with devenv-driver: {}", e);
            return Err(e);
        }

        // Assemble /nix/store from the erofs image and a tmpfs overlay
        if let Err(e) = mount_store_overlay() {
            error!("Failed to mount nix store overlay: {}", e);
            return Err(e);
        }

        // Set hostname before chroot
        if let Err(e) = set_hostname("devenv-vm") {
            error!("Failed to set hostname: {}", e);
        }

        // Use chroot to switch to the new root
        if let Err(e) = pivot_to_devenv_root() {
            error!("Failed to chroot to {}: {}", NEW_ROOT, e);
            return Err(e);
        }

        info!("Successfully switched to new root filesystem");

        // Warm the guest page cache for the driver binary and its shared
        // libraries. Sequential reads over virtiofs are much faster than the
        // demand-paged faults the dynamic linker generates on its own; the
        // reads race the driver startup below, so the threads are not joined.
        prewarm_driver_files("/prewarm-list");

        // Run devenv-driver as a child while init remains PID 1. Staying PID 1
        // keeps the pid1 crate inside the driver a no-op, avoiding a re-exec
        // of the large driver binary, and leaves a root process around to reap
        // orphaned zombies and halt the VM if the driver exits early (the
        // driver itself cannot halt after it drops privileges).
        let driver_path = "/bin/devenv-driver";
        info!("Spawning {}", driver_path);

        let child = match std::process::Command::new(driver_path).spawn() {
            Ok(child) => child,
            Err(e) => {
                error!("Failed to spawn devenv-driver: {}", e);
                halt_vm();
            }
        };

        let driver_pid = nix::unistd::Pid::from_raw(child.id() as i32);

        loop {
            match nix::sys::wait::waitpid(None, None) {
                Ok(status) if status.pid() == Some(driver_pid) => {
                    info!("devenv-driver exited ({:?}), halting VM", status);
                    halt_vm();
                }
                // Reaped an orphaned process that was reparented to PID 1
                Ok(_) => {}
                Err(nix::errno::Errno::EINTR) => {}
                Err(e) => {
                    error!("waitpid failed: {}", e);
                    halt_vm();
                }
            }
        }
    }

    /// Read the files listed in `list_path` into the page cache using a few
    /// parallel threads. Best-effort: missing list or files are ignored.
    fn prewarm_driver_files(list_path: &str) {
        let Ok(list) = std::fs::read_to_string(list_path) else {
            tracing::warn!("No prewarm list at {}, skipping prewarm", list_path);
            return;
        };

        let paths: Vec<String> = list
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .map(str::to_owned)
            .collect();

        const PREWARM_THREADS: usize = 8;
        let chunk_size = paths.len().div_ceil(PREWARM_THREADS).max(1);
        for chunk in paths.chunks(chunk_size) {
            let chunk = chunk.to_vec();
            std::thread::spawn(move || {
                for path in chunk {
                    let _ = std::fs::read(&path);
                }
            });
        }
    }

    /// Sync filesystems and power off the VM, never returning.
    /// RB_POWER_OFF (ACPI S5) makes cloud-hypervisor exit; RB_HALT_SYSTEM
    /// would only park the vcpus and leave the VMM process running.
    fn halt_vm() -> ! {
        unsafe { libc::sync() };
        let _ = nix::sys::reboot::reboot(nix::sys::reboot::RebootMode::RB_POWER_OFF);
        // Powering off failed; exit and let the kernel report the dead init
        std::process::exit(1);
    }
}

#[cfg(target_os = "macos")]
mod macos {
    use color_eyre::eyre::Result;

    pub fn main() -> Result<()> {
        println!("This is a dummy main for macOS to allow compilation");
        Ok(())
    }
}

fn main() -> color_eyre::eyre::Result<()> {
    #[cfg(target_os = "linux")]
    {
        linux::main()
    }

    #[cfg(target_os = "macos")]
    {
        macos::main()
    }

    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    {
        panic!("Unsupported operating system");
    }
}
