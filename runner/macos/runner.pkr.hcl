packer {
  required_plugins {
    tart = {
      version = ">= 1.12.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "vm_name" {
  type = string
}

variable "macos_version" {
  type = string
}

variable "devenv_driver_path" {
  type    = string
  description = "Nix store path to the devenv-driver. This will be copied to the VM."
}

variable "devenv_nix_path" {
  type    = string
  description = "Nix store path to devenv-nix. This will be copied to the VM."
}

source "tart-cli" "tart" {
  vm_base_name = "ghcr.io/cirruslabs/macos-${var.macos_version}-vanilla:latest"
  vm_name      = var.vm_name
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = 50
  ssh_password = "admin"
  ssh_username = "admin"
  ssh_timeout  = "120s"
}

build {
  sources = ["source.tart-cli.tart"]

  provisioner "file" {
    source      = "data/limit.maxfiles.plist"
    destination = "~/limit.maxfiles.plist"
  }

  provisioner "shell" {
    inline = [
      "echo 'Configuring maxfiles...'",
      "sudo mv ~/limit.maxfiles.plist /Library/LaunchDaemons/limit.maxfiles.plist",
      "sudo chown root:wheel /Library/LaunchDaemons/limit.maxfiles.plist",
      "sudo chmod 0644 /Library/LaunchDaemons/limit.maxfiles.plist",
      "echo 'Disabling spotlight...'",
      "sudo mdutil -a -i off",
    ]
  }

  # Create a symlink for bash compatibility
  provisioner "shell" {
    inline = [
      "touch ~/.zprofile",
      "ln -s ~/.zprofile ~/.profile",
      "echo \"export LANG=en_US.UTF-8\" >> ~/.zprofile",
    ]
  }

  # Install Nix
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm --diagnostic-endpoint='' --extra-conf='trusted-users = root admin'",
      # Link the certificate bundle to the usual location in /etc/ssl/certs/
      "sudo ln -s /nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt",
    ]
  }

  # Install packages
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "nix profile install nixpkgs#bash nixpkgs#cacert nixpkgs#git-lfs nixpkgs#jq nixpkgs#zip nixpkgs#unzip",
      "git lfs install",
      "sudo softwareupdate --install-rosetta --agree-to-license"
    ]
  }

  // Add GitHub to known hosts
  // Similar to https://github.com/actions/runner-images/blob/main/images/macos/scripts/build/configure-ssh.sh
  provisioner "shell" {
    inline = [
      "mkdir -p ~/.ssh"
    ]
  }
  provisioner "file" {
    source      = "data/github_known_hosts"
    destination = "~/.ssh/known_hosts"
  }

  provisioner "shell" {
    inline = [
      "sudo safaridriver --enable",
    ]
  }

  # Enable UI automation, see https://github.com/cirruslabs/macos-image-templates/issues/136
  provisioner "shell" {
    script = "scripts/automationmodetool.expect"
  }

  // some other health checks
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "test -f ~/.ssh/known_hosts"
    ]
  }

  // Copy the devenv-driver to the VM's Nix store
  provisioner "shell-local" {
    inline = [
      "echo 'Querying IP address...'",
      "ip=$(tart ip ${var.vm_name})",
      "echo \"IP address: $ip\"",

      "echo 'Copying devenv-driver: ${var.devenv_driver_path}'",
      "sshpass -p 'admin' nix copy --to ssh://admin@$ip ${var.devenv_driver_path} --no-check-sigs",

      "echo 'Copying devenv-nix: ${var.devenv_nix_path}'",
      "sshpass -p 'admin' nix copy --to ssh://admin@$ip ${var.devenv_nix_path} --no-check-sigs",

      # TODO: add a gc root or install devenv-driver into someone's profile?
    ]
    environment_vars = [
      "NIX_SSHOPTS=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no"
    ]
  }

  // Disable SSH and create launchd daemon for devenv-driver
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",

      "echo 'Creating working directory for devenv-driver...'",
      "sudo mkdir -p /var/lib/devenv-driver",

      "echo 'Creating log directory for devenv-driver...'",
      "sudo mkdir -p /var/log/devenv-driver",

      "echo 'Creating devenv-driver launch daemon...'",
      "cat > ~/sh.devenv.driver.plist << 'EOL'",
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
      "<plist version=\"1.0\">",
      "<dict>",
      "    <key>Label</key>",
      "    <string>sh.devenv.driver</string>",
      "    <key>ProgramArguments</key>",
      "    <array>",
      "        <string>/bin/sh</string>",
      "        <string>-c</string>",
      "        <string>/bin/wait4path /nix/store &amp;&amp; devenv-driver</string>",
      "    </array>",
      "    <key>WorkingDirectory</key>",
      "    <string>/var/lib/devenv-driver</string>",
      "    <key>RunAtLoad</key>",
      "    <true/>",
      "    <key>KeepAlive</key>",
      "    <false/>",
      "    <key>StandardOutPath</key>",
      "    <string>/var/log/devenv-driver/devenv-driver.log</string>",
      "    <key>StandardErrorPath</key>",
      "    <string>/var/log/devenv-driver/devenv-driver.log</string>",
      "    <key>EnvironmentVariables</key>",
      "    <dict>",
      "        <key>PATH</key>",
      "        <string>${var.devenv_driver_path}/bin:/nix/var/nix/profiles/default/bin:/bin:/usr/bin:/usr/local/bin</string>",
      # These don't work for some reason
      # "        <key>SSL_CERT_FILE</key>",
      # "        <string>/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt</string>",
      # "        <key>NIX_SSL_CERT_FILE</key>",
      # "        <string>/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt</string>",
      "        <key>DEVENV_NIX</key>",
      "        <string>${var.devenv_nix_path}</string>",
      "    </dict>",
      # Remove resource limits
      "    <key>ProcessType</key>",
      "    <string>Interactive</string>",
      # Create a new security session
      # "    <key>SessionCreate</key>",
      # "    <true/>",
      "</dict>",
      "</plist>",
      "EOL",

      # Install and adjust plist permissions
      "sudo mv ~/sh.devenv.driver.plist /Library/LaunchDaemons/sh.devenv.driver.plist",
      "sudo chown root:wheel /Library/LaunchDaemons/sh.devenv.driver.plist",
      "sudo chmod 0644 /Library/LaunchDaemons/sh.devenv.driver.plist",

      "echo 'Devenv driver launch daemon installed'"
    ]
  }
}

