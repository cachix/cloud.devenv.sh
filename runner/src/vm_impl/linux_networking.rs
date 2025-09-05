use eyre::{Result, WrapErr, eyre};
use std::io::Write;
use std::net::Ipv4Addr;
use std::process::Command;
use tracing;

/// Default gateway IP for VM networking
pub const VM_GATEWAY_IP: Ipv4Addr = Ipv4Addr::new(10, 0, 0, 1);

/// Default subnet mask for VM networking (/24)
pub const VM_SUBNET_MASK: &str = "255.255.255.0";

/// Default VM subnet for NAT rules
pub const VM_SUBNET: &str = "10.0.0.0/24";

/// Setup host networking by enabling IP forwarding and configuring NAT
pub fn setup_host_networking() -> Result<()> {
    tracing::info!("Setting up host networking for VMs");

    // Enable IP forwarding
    tracing::info!("Enabling IP forwarding for VM networking");

    let output = Command::new("sysctl")
        .args(&["-w", "net.ipv4.ip_forward=1"])
        .output()
        .wrap_err("Failed to execute sysctl command")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(eyre!(
            "Failed to enable IP forwarding: {}. Please run: sysctl -w net.ipv4.ip_forward=1",
            stderr.trim()
        ));
    }

    tracing::info!("IP forwarding enabled");

    // Setup NAT with nftables in a single atomic operation
    setup_nat_rules()?;

    tracing::info!("Host networking setup complete");
    Ok(())
}

/// Setup NAT rules with nftables in a single atomic operation
fn setup_nat_rules() -> Result<()> {
    tracing::info!("Setting up NAT rules with nftables");

    // Define all NAT rules in a single nftables script
    // This creates the table and chains if they don't exist, and adds the rules
    let nft_rules = format!(
        r#"
# Create or update the devenv NAT table
table ip devenv_nat {{
    # Postrouting chain for source NAT (masquerading)
    chain postrouting {{
        type nat hook postrouting priority srcnat; policy accept;

        # Masquerade traffic from VM subnet going out through non-vmtap interfaces
        # This allows VMs to access the internet through the host
        ip saddr {} oifname != "vmtap*" masquerade
    }}

    # Prerouting chain for destination NAT (if needed in future)
    chain prerouting {{
        type nat hook prerouting priority dstnat; policy accept;
    }}
}}
"#,
        VM_SUBNET
    );

    // Execute nftables rules
    let mut child = Command::new("nft")
        .arg("-f")
        .arg("-")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .wrap_err("Failed to spawn nft command")?;

    // Write rules to stdin
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(nft_rules.as_bytes())
            .wrap_err("Failed to write nft rules to stdin")?;
    }

    // Wait for command to complete
    let output = child
        .wait_with_output()
        .wrap_err("Failed to execute nft command")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(eyre!(
            "Failed to setup NAT rules: {}. Please run: nft",
            stderr.trim()
        ));
    }

    tracing::info!("NAT rules configured successfully");
    Ok(())
}

/// Configure network interface inside the VM
pub async fn configure_network() -> Result<()> {
    tracing::debug!("Configuring network interface");

    // Wait for network interface to appear (cloud-hypervisor creates it)
    let interface = wait_for_network_interface().await?;

    // The IP configuration is passed via kernel cmdline by cloud-hypervisor
    // Format: "ip=<client-ip>:<server-ip>:<gw-ip>:<netmask>:<hostname>:<device>:<autoconf>"
    let cmdline = std::fs::read_to_string("/proc/cmdline").unwrap_or_default();

    if let Some(ip_config) = parse_ip_from_cmdline(&cmdline) {
        configure_static_ip(&interface, &ip_config).await?;
    } else {
        // Just bring up the interface and let DHCP handle it (if available)
        bring_interface_up(&interface).await?;
    }

    // Test DNS resolution
    test_dns_resolution().await?;

    Ok(())
}

/// Wait for network interface to be created by hypervisor
async fn wait_for_network_interface() -> Result<String> {
    let interface = "eth0";

    // Wait for eth0 to be created
    for i in 0..10 {
        if std::path::Path::new(&format!("/sys/class/net/{}", interface)).exists() {
            tracing::debug!("Found network interface: {}", interface);
            return Ok(interface.to_string());
        }

        if i == 9 {
            return Err(eyre!(
                "Network interface {} not found after 10 seconds",
                interface
            ));
        }

        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
    }

    Err(eyre!("Failed to find network interface {}", interface))
}

/// Parse IP configuration from kernel command line
fn parse_ip_from_cmdline(cmdline: &str) -> Option<IpConfig> {
    cmdline
        .split_whitespace()
        .find(|s| s.starts_with("ip="))
        .and_then(|s| s.strip_prefix("ip="))
        .and_then(|config| {
            let parts: Vec<&str> = config.split(':').collect();
            if parts.len() >= 4 {
                Some(IpConfig {
                    address: parts[0].to_string(),
                    gateway: parts[2].to_string(),
                    netmask: parts[3].to_string(),
                })
            } else {
                None
            }
        })
}

struct IpConfig {
    address: String,
    gateway: String,
    netmask: String,
}

/// Configure static IP on interface
async fn configure_static_ip(interface: &str, config: &IpConfig) -> Result<()> {
    // Calculate prefix from netmask (simple case for 255.255.255.0)
    let prefix = if config.netmask == "255.255.255.0" {
        "24"
    } else {
        return Err(eyre!("Unsupported netmask: {}", config.netmask));
    };

    // Add IP address
    let output = Command::new("ip")
        .args(&[
            "addr",
            "add",
            &format!("{}/{}", config.address, prefix),
            "dev",
            interface,
        ])
        .output()
        .wrap_err("Failed to set IP address")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        // Ignore "File exists" error - IP might already be configured
        if !stderr.contains("File exists") {
            return Err(eyre!("Failed to set IP address: {}", stderr));
        }
    }

    // Bring interface up
    bring_interface_up(interface).await?;

    // Add default route
    let output = Command::new("ip")
        .args(&["route", "add", "default", "via", &config.gateway])
        .output()
        .wrap_err("Failed to add default route")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        // Ignore "File exists" error - route might already exist
        if !stderr.contains("File exists") {
            return Err(eyre!("Failed to add default route: {}", stderr));
        }
    }

    tracing::debug!(
        "Network configured: IP={}, Gateway={}",
        config.address,
        config.gateway
    );

    // Test DNS resolution
    test_dns_resolution().await?;

    Ok(())
}

/// Simply bring the interface up
async fn bring_interface_up(interface: &str) -> Result<()> {
    let output = Command::new("ip")
        .args(&["link", "set", interface, "up"])
        .output()
        .wrap_err("Failed to bring up interface")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(eyre!("Failed to bring up interface: {}", stderr));
    }

    tracing::debug!("Interface {} is up", interface);
    Ok(())
}

async fn test_dns_resolution() -> Result<()> {
    tracing::debug!("Testing DNS resolution for github.com");

    // Use nslookup from dnsutils package
    let output = Command::new("nslookup")
        .args(&["github.com"])
        .output()
        .wrap_err("Failed to execute nslookup command")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        return Err(eyre!(
            "DNS resolution failed for devenv.sh\nstdout: {}\nstderr: {}",
            stdout.trim(),
            stderr.trim()
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    tracing::debug!("DNS resolution successful:\n{}", stdout.trim());

    Ok(())
}
