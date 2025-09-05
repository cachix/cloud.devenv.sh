#![cfg(target_os = "linux")]

use color_eyre::eyre::{eyre, Result};
use nix::{
    mount::{self, MsFlags},
    unistd,
};
use std::path::Path;
use tracing::{debug, error, info};

/// Represent a filesystem mount point
pub struct MountPoint<'a> {
    pub device: &'a str,
    pub mount_path: &'a str,
    pub fs_type: &'a str,
    pub options: &'a [&'a str],
}

/// Mount the essential virtual filesystems needed before other operations
pub fn mount_essential_filesystems() -> Result<()> {
    let filesystems = [
        MountPoint {
            device: "proc",
            mount_path: "/proc",
            fs_type: "proc",
            options: &[],
        },
        MountPoint {
            device: "sysfs",
            mount_path: "/sys",
            fs_type: "sysfs",
            options: &[],
        },
        MountPoint {
            device: "devtmpfs",
            mount_path: "/dev",
            fs_type: "devtmpfs",
            options: &[],
        },
        MountPoint {
            device: "tmpfs",
            mount_path: "/tmp",
            fs_type: "tmpfs",
            options: &["size=2G"],
        },
    ];

    for mount in &filesystems {
        mount_filesystem(mount.device, mount.mount_path, mount.fs_type, mount.options)?;
    }

    Ok(())
}

/// Mount a single filesystem using the MountPoint struct
pub fn mount_filesystem(
    device: &str,
    mountpoint: &str,
    fstype: &str,
    options: &[&str],
) -> Result<()> {
    debug!("Mounting {} at {}", fstype, mountpoint);

    // Create the mountpoint directory if it doesn't exist
    std::fs::create_dir_all(mountpoint)?;

    // Convert mount options to MsFlags and collect data options
    let mut flags = MsFlags::empty();
    let mut data_options = Vec::new();

    // Common flags mapping - expand as needed
    for option in options {
        match *option {
            "nodev" => flags |= MsFlags::MS_NODEV,
            "noexec" => flags |= MsFlags::MS_NOEXEC,
            "nosuid" => flags |= MsFlags::MS_NOSUID,
            "ro" => flags |= MsFlags::MS_RDONLY,
            "noatime" => flags |= MsFlags::MS_NOATIME,
            // For options like size=2G, mode=1777, etc., pass them as data
            opt if opt.contains('=') => data_options.push(opt),
            _ => {} // Ignore other options for now
        }
    }

    // Join data options with commas
    let data = if data_options.is_empty() {
        None
    } else {
        Some(data_options.join(","))
    };

    // Use the nix mount function
    match mount::mount(
        Some(device),
        mountpoint,
        Some(fstype),
        flags,
        data.as_deref(),
    ) {
        Ok(_) => Ok(()),
        Err(e) => {
            error!("Failed to mount {} at {}: {}", fstype, mountpoint, e);
            Err(eyre!("Mount operation failed: {}", e))
        }
    }
}

/// Create essential symlinks
pub fn create_symlinks() -> Result<()> {
    // Common symlinks found in Linux systems
    let symlinks = [
        ("/proc/self/fd", "/dev/fd"),
        ("/proc/self/fd/0", "/dev/stdin"),
        ("/proc/self/fd/1", "/dev/stdout"),
        ("/proc/self/fd/2", "/dev/stderr"),
    ];

    for (target, link) in symlinks {
        debug!("Creating symlink {} -> {}", link, target);

        // Remove existing symlink if it exists
        if Path::new(link).exists() {
            std::fs::remove_file(link)?;
        }

        // Create the symlink
        std::os::unix::fs::symlink(target, link)?;
    }

    Ok(())
}

/// Perform basic system initialization
pub fn init_system() -> Result<()> {
    // Set up /etc/passwd and /etc/group minimally if they don't exist
    if !Path::new("/etc/passwd").exists() {
        info!("Creating minimal /etc/passwd");
        std::fs::write("/etc/passwd", "root:x:0:0:root:/root:/bin/sh\n")?;
    }

    if !Path::new("/etc/group").exists() {
        info!("Creating minimal /etc/group");
        std::fs::write("/etc/group", "root:x:0:\n")?;
    }

    Ok(())
}

/// Set system hostname
pub fn set_hostname(hostname: &str) -> Result<()> {
    info!("Setting hostname to {}", hostname);
    unistd::sethostname(hostname)?;
    Ok(())
}

/// Path to the new root filesystem
pub const NEW_ROOT: &str = "/mnt";

/// Mount the root filesystem using devenv-driver
pub fn mount_root_filesystem() -> Result<()> {
    // Mount virtiofs filesystem
    info!("Mounting rootfs using virtiofs");

    // Create mountpoint if it doesn't exist
    std::fs::create_dir_all(NEW_ROOT)?;

    match mount::mount(
        Some("rootfs"),
        NEW_ROOT,
        Some("virtiofs"),
        MsFlags::empty(),
        None::<&str>,
    ) {
        Ok(_) => {
            info!(
                "Successfully mounted devenv root filesystem at {}",
                NEW_ROOT
            );
            Ok(())
        }
        Err(e) => {
            error!("Failed to mount virtiofs rootfs at {}: {}", NEW_ROOT, e);
            Err(eyre!("Failed to mount virtiofs rootfs: {}", e))
        }
    }
}

/// Use chroot to switch to the mounted devenv root filesystem
pub fn pivot_to_devenv_root() -> Result<()> {
    // Check that the new root target exists
    if !std::path::Path::new(NEW_ROOT).exists() {
        return Err(eyre!("Devenv root directory does not exist: {}", NEW_ROOT));
    }

    info!("Preparing to chroot to {}", NEW_ROOT);

    // Mount essential filesystems in the new root environment
    for mount_point in &["proc", "sys", "dev", "run", "tmp"] {
        let target = format!("{NEW_ROOT}/{mount_point}");

        // Create target directory if it doesn't exist
        std::fs::create_dir_all(&target)?;

        // Bind mount from source to target using nix
        let source_path = format!("/{mount_point}");
        match mount::mount(
            Some(source_path.as_str()),
            target.as_str(),
            None::<&str>,
            MsFlags::MS_BIND,
            None::<&str>,
        ) {
            Ok(_) => {}
            Err(e) => {
                return Err(eyre!(
                    "Failed to bind mount /{} to {}: {}",
                    mount_point,
                    target,
                    e
                ));
            }
        }

        debug!("Bind mounted /{} to {}", mount_point, target);
    }

    // Use chroot instead of pivot_root since we're likely running on an initial ramfs
    // which cannot be fully unmounted/pivoted away from
    info!("Using chroot to switch root");

    // Change root to new_root
    nix::unistd::chroot(NEW_ROOT)?;
    std::env::set_current_dir("/")?;

    info!("Successfully chrooted to devenv filesystem");

    // Mount /dev/pts inside the chroot since bind mounting /dev doesn't include submounts
    info!("Mounting /dev/pts in the new root");
    std::fs::create_dir_all("/dev/pts")?;
    match mount::mount(
        Some("devpts"),
        "/dev/pts",
        Some("devpts"),
        MsFlags::MS_NOSUID | MsFlags::MS_NOEXEC,
        Some("mode=620,ptmxmode=0666,gid=100"),
    ) {
        Ok(_) => {
            debug!("Successfully mounted /dev/pts");
        }
        Err(e) => {
            error!("Failed to mount /dev/pts: {}", e);
            // Continue anyway as this might not be critical for all operations
        }
    }

    Ok(())
}
