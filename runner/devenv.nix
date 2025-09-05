{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  # Import our package definitions
  packages = pkgs.callPackage ../package.nix { };
  # Extract binaries
  inherit (packages) devenv-init devenv-driver;

  # Create a custom initrd with our init binary
  customInitrd = pkgs.runCommand "custom-initrd" { } ''
    mkdir -p $out/initrd-tree/{bin,sbin,proc,sys,dev,tmp,run,etc}

    cp ${devenv-init}/bin/init $out/initrd-tree/init
    chmod +x $out/initrd-tree/init

    # Create the initrd using cpio
    cd $out/initrd-tree
    find . | ${pkgs.cpio}/bin/cpio -H newc -o | gzip -9 > $out/initrd
  '';

  # Create a resolv.conf file with DNS configuration
  resolvConf = pkgs.writeText "resolv.conf" ''
    nameserver 1.1.1.1
    nameserver 8.8.8.8
  '';

  # Create passwd file
  passwdFile = pkgs.writeText "passwd" ''
    root:x:0:0:root:/root:/bin/sh
    devenv:x:1000:100:devenv:/home/devenv:/bin/sh
  '';

  # Create group file
  groupFile = pkgs.writeText "group" ''
    root:x:0:
    users:x:100:devenv
  '';

  # Create nix.conf for single-user mode
  nixConf = pkgs.writeText "nix.conf" ''
    # Single-user mode configuration
    build-users-group =
    allowed-users = *
    trusted-users = devenv
  '';

  # Create PAM configuration for su
  pamSu = pkgs.writeText "su" ''
    auth     sufficient pam_permit.so
    account  sufficient pam_permit.so
    password sufficient pam_permit.so
    session  sufficient pam_permit.so
  '';

  # Create an activation script that sets up /etc
  etcSetup = pkgs.runCommand "etc-setup" { } ''
    mkdir -p $out/etc/nix
    mkdir -p $out/etc/pam.d
    cp ${resolvConf} $out/etc/resolv.conf
    cp ${passwdFile} $out/etc/passwd
    cp ${groupFile} $out/etc/group
    cp ${nixConf} $out/etc/nix/nix.conf
    cp ${pamSu} $out/etc/pam.d/su
  '';

  # Store paths to register in VM
  storePaths = [
    pkgs.pkgsStatic.bash
    pkgs.coreutils
    devenv-driver
    pkgs.dockerTools.caCertificates
    etcSetup
    # networking
    pkgs.iproute2
    pkgs.dnsutils
    # user management
    pkgs.sudo-rs
  ];

  # Get devenv's patched nix from nixpkgs
  devenv-nix = inputs.nix.packages.${pkgs.stdenv.system}.nix-cli;

  # Create closure info for store paths
  sdClosureInfo = pkgs.buildPackages.closureInfo { rootPaths = storePaths ++ [ devenv-nix ]; };

  # Create a pre-built nix store directory with all required store paths
  nixStoreImage = pkgs.runCommand "nix-store-image" { } ''
    mkdir -p $out/nix/store

    # Copy all store paths and their dependencies from the closure
    while IFS= read -r path; do
      if [[ "$path" == /nix/store/* ]]; then
        store_component=$(basename "$path")
        dest_path="$out/nix/store/$store_component"
        
        # Skip if already exists to avoid duplicates
        if [ ! -e "$dest_path" ]; then
          if [ -e "$path" ]; then
            echo "Copying $path"
            cp -r --no-dereference --preserve=all "$path" "$out/nix/store/"
          fi
        else
          echo "Skipping duplicate: $path"
        fi
      fi
    done < ${sdClosureInfo}/registration

    # Also copy the registration file for reference
    cp ${sdClosureInfo}/registration $out/registration
  '';

  # Create the filesystem environment
  rootfs = pkgs.buildEnv {
    name = "devenv-rootfs";
    paths = storePaths ++ [ sdClosureInfo ];
    pathsToLink = [
      "/"
    ];
    postBuild = ''
      # Don't create the symlink here - it will be created at runtime
      # Just store the nix path information for the VM to use
      echo "${devenv-nix}" > $out/nix-binary-path
    '';
  };

  kernel = pkgs.buildLinux ({
    inherit (pkgs.linuxPackages_latest.kernel) src version modDirVersion;
    autoModules = false;
    kernelPreferBuiltin = true;
    ignoreConfigErrors = true;
    kernelPatches = [ ];
    structuredExtraConfig = with pkgs.lib.kernel; {
      FUSE_FS = option yes;
      DAX_DRIVER = option yes;
      DAX = option yes;
      FS_DAX = option yes;
      VIRTIO_FS = yes;
      VIRTIO = yes;
      VIRTIO_NET = yes;
      VIRTIO_CONSOLE = yes;
      TUN = yes;
      ZONE_DEVICE = option yes;
      VHOST_VSOCK = yes;
      VSOCKETS = yes;
      VIRTIO_VSOCKETS = yes;
      VIRTIO_VSOCKETS_COMMON = yes;
    };
  });

  linuxResources = pkgs.runCommand "linux-resources" { } ''
    mkdir -p $out
    cp ${kernel}/*Image $out/vmlinux
    cp ${customInitrd}/initrd $out/initrd
    ln -s ${rootfs} $out/rootfs
    ln -s ${nixStoreImage} $out/nix-store-image
  '';

  # Create capability-wrapping function that can be used for both binaries
  mkCapWrapper =
    name: originalPath: capabilities:
    pkgs.writeShellScriptBin name ''
      #!/usr/bin/env bash
      set -e

      # Source binary path and local destination
      ORIGINAL_BIN="${originalPath}"
      LOCAL_BIN_DIR="$DEVENV_STATE/bin"
      LOCAL_BIN="$LOCAL_BIN_DIR/${name}"

      # Create local bin directory if it doesn't exist
      mkdir -p "$LOCAL_BIN_DIR"

      # Check if we need to copy the binary (source is newer or target doesn't exist)
      if [ ! -f "$LOCAL_BIN" ] || [ "$ORIGINAL_BIN" -nt "$LOCAL_BIN" ]; then
        echo "Copying ${name} to $LOCAL_BIN"
        cp "$ORIGINAL_BIN" "$LOCAL_BIN"
        chmod +x "$LOCAL_BIN"
      fi

      # Check if the binary has the necessary capabilities by testing if any capabilities are set
      CURRENT_CAPS=$(getcap "$LOCAL_BIN" 2>/dev/null || echo "")
      if [ -z "$CURRENT_CAPS" ] || ! echo "$CURRENT_CAPS" | grep -q "cap_"; then
        echo "${name} needs ${capabilities} capabilities."
        echo ""
        echo "Please run the following command to set them:"
        echo ""
        echo "  sudo setcap ${capabilities}=ep $LOCAL_BIN"
        echo ""
        exit 1
      fi

      # Execute the local binary with all arguments
      exec "$LOCAL_BIN" "$@"
    '';

  # Create wrappers for both binaries
  cloud-hypervisor-wrapper =
    mkCapWrapper "cloud-hypervisor" "${pkgs.cloud-hypervisor}/bin/cloud-hypervisor"
      "cap_net_admin,cap_sys_admin,cap_net_raw";

  virtiofsd-wrapper =
    mkCapWrapper "virtiofsd" "${pkgs.virtiofsd}/bin/virtiofsd"
      "cap_chown,cap_dac_override,cap_fowner,cap_sys_admin";

  nft-wrapper = mkCapWrapper "nft" "${pkgs.nftables}/bin/nft" "cap_net_admin";
  libcap-wrapper = mkCapWrapper "libcap" "${pkgs.libcap}/bin/tuntap" "cap_net_admin";

  sysctl-wrapper = mkCapWrapper "sysctl" "${pkgs.procps}/bin/sysctl" "cap_net_admin,cap_sys_admin";
in
{
  config = lib.mkMerge [
    {
      outputs = {
        inherit (packages) devenv-backend;
      };
    }
    (lib.mkIf pkgs.stdenv.isLinux {
      env.RESOURCES_DIR = linuxResources;
      packages = [
        cloud-hypervisor-wrapper
        virtiofsd-wrapper
        nft-wrapper
        libcap-wrapper
        sysctl-wrapper
      ];

      outputs = {
        inherit linuxResources;
      };
    })
    (lib.mkIf pkgs.stdenv.isDarwin {
      env.RESOURCES_DIR = "${config.devenv.root}/runner/macos/runner-vm";

      outputs = {
        inherit devenv-driver devenv-nix;
      };

      packages = [
        pkgs.packer
        pkgs.sshpass
        pkgs.tart
      ];

      scripts.macos-launch-vm.exec = ''
        set -euo pipefail

        echo "Building launcher..."
        cargo build -p devenv-runner --bin devenv-launcher
        echo "Signing launcher..."
        codesign --force --entitlements runner/resources/runner.entitlements --sign - target/debug/devenv-launcher
        echo "Launching macOS VM..."
        ./target/debug/devenv-launcher
      '';

      scripts.build-macos-vm.exec = ''
        set +euo pipefail

        echo "Building devenv packages..." >&2
        devenv_driver=$(devenv build outputs.packages.devenv-driver)
        devenv_nix=$(devenv build outputs.packages.devenv-nix)
        echo "Using devenv driver: $devenv_driver" >&2
        echo "Using devenv nix: $devenv_nix" >&2

        echo "Building macOS VM image..." >&2
        pushd runner/macos
        export TART_HOME=.tart
        packer init runner.pkr.hcl

        packer build \
          -var vm_name=devenv-runner \
          -var macos_version=sequoia \
          -var devenv_driver_path=$devenv_driver \
          -var devenv_nix_path=$devenv_nix \
          runner.pkr.hcl
        if [ $? -ne 0 ]; then
          echo "Packer build failed" >&2
          exit 1
        fi
        mv -f $TART_HOME/vms/devenv-runner/* runner-vm/
        popd
      '';
    })
  ];
}
