#![cfg_attr(target_os = "linux", doc = "Linux init system implementation")]

#[cfg(target_os = "linux")]
mod linux {
    use clap::Parser;
    use color_eyre::eyre::Result;
    use devenv_init::{
        mount_essential_filesystems, mount_root_filesystem, pivot_to_devenv_root, set_hostname,
        NEW_ROOT,
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

        // Execute devenv-driver, replacing the current process
        let driver_path = "/bin/devenv-driver";
        info!("Executing {}", driver_path);

        use std::os::unix::process::CommandExt;
        let err = std::process::Command::new(driver_path).exec();

        // If we get here, exec failed
        error!("Failed to execute devenv-driver: {}", err);
        return Err(err.into());
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
