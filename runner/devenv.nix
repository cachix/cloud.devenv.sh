{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  rustToolchain = pkgs.rust-bin.stable.latest.default;

  # Import our package definitions
  packages = pkgs.callPackage ../package.nix {
    nix = inputs.nix.packages.${pkgs.system}.nix;
    rustc = rustToolchain;
    cargo = rustToolchain;
  };
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

  # Files the dynamic linker maps when devenv-driver starts. devenv-init
  # reads these into the guest page cache in parallel before spawning the
  # driver; sequential reads over virtiofs are much faster than the
  # demand-paged faults the linker would generate on its own.
  driverPrewarmList = pkgs.runCommand "driver-prewarm-list" { } ''
    mkdir -p $out
    {
      echo "${devenv-driver}/bin/devenv-driver"
      ${pkgs.glibc.bin}/bin/ldd ${devenv-driver}/bin/devenv-driver \
        | grep -oE '/nix/store/[^ )]+' || true
    } | sort -u > $out/prewarm-list
  '';

  # Store paths to register in VM
  storePaths = [
    pkgs.pkgsStatic.bash
    pkgs.coreutils
    devenv-driver
    pkgs.dockerTools.caCertificates
    etcSetup
    driverPrewarmList
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

      # The VM boots a kernel directly with a virtiofs root and virtio
      # devices only. kernelPreferBuiltin turns the distro config's module
      # drivers into built-ins that register on every boot, so drop the
      # hardware subsystems this VM can never see to cut boot time and
      # kernel size.
      DRM = lib.mkForce no;
      SOUND = lib.mkForce no;
      USB_SUPPORT = lib.mkForce no;
      HID_SUPPORT = lib.mkForce no;
      WLAN = lib.mkForce no;
      WIRELESS = lib.mkForce no;
      CFG80211 = lib.mkForce no;
      BT = lib.mkForce no;
      NFC = lib.mkForce no;
      ETHERNET = lib.mkForce no;
      HYPERV = lib.mkForce no;
      INFINIBAND = lib.mkForce no;
      SCSI = lib.mkForce no;
      ATA = lib.mkForce no;
      MD = lib.mkForce no;
      AGP = lib.mkForce no;
      IMA = lib.mkForce no;
      INTEGRITY = lib.mkForce no;
    };
  });

  linuxResources = pkgs.runCommand "linux-resources" { } ''
    mkdir -p $out
    cp ${kernel}/*Image $out/vmlinux
    cp ${customInitrd}/initrd $out/initrd
    ln -s ${rootfs} $out/rootfs
    ln -s ${nixStoreImage} $out/nix-store-image
  '';

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

      processes.runner.linux.capabilities = [
        "cap_net_admin" # nft, sysctl, tuntap, cloud-hypervisor
        "cap_net_raw" # cloud-hypervisor
        "cap_sys_admin" # cloud-hypervisor, sysctl, virtiofsd
        "cap_chown" # virtiofsd
        "cap_dac_override" # virtiofsd
        "cap_fowner" # virtiofsd
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
