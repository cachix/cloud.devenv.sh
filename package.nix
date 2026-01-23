{
  lib,
  pkgsStatic,
  rustPlatform,
  pkg-config,
  openssl,
  dbus,
  nix,
  protobuf,
  llvmPackages,
  boehmgc,
}:

let
  # Common configuration for Rust packages
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "axum-typed-websockets-0.6.0" = "sha256-uou03y7v6gtNDrt2Dcb0NcSHNfZqExWBfTYc4sx5MQY=";
      "devenv-2.0.0" = "sha256-pf5bnn9Q99gISJK4b1Xc1RyX4SHcogUPNxz7EBMYaGs=";
      "iocraft-0.7.16" = "sha256-MBwTP8HeJnXnnJqsKkrKIuSk2wxFChotwO58/1JB1js=";
      "nix-bindings-bindgen-raw-0.1.0" = "sha256-rSswQdG/9/oe28Q0MTzQJ9jEGcFPEyfxVXvfmtlr71I=";
      "secretspec-0.6.1" = "sha256-gOmxzGTbKWVXkv2ZPmxxGUV1LB7vOYd7BXqaVd2LaFc=";
      "ser_nix-0.1.2" = "sha256-E1vPfhVDkeSt6OxYhnj8gYadUpJJDLRF5YiUkujQsCQ=";
    };
  };

  rustCommon = {
    doCheck = false;
    doDoc = false;
    inherit cargoLock;
    nativeBuildInputs = [
      pkg-config
    ];
    RUSTFLAGS = "--cfg tokio_unstable --cfg tracing_unstable";
  };

  # Build our init binary from the Rust code, statically linked
  devenv-init = pkgsStatic.rustPlatform.buildRustPackage (
    rustCommon
    // {
      src = lib.cleanSource ./.;
      pname = "devenv-init";
      version = "0.1.0";
      RUSTFLAGS = "-C target-feature=+crt-static";
      buildInputs = [
        pkgsStatic.openssl
      ];
      cargoBuildFlags = [
        "--bin"
        "init"
      ];
    }
  );

  # Build the driver binary from the Rust code
  devenv-driver = rustPlatform.buildRustPackage (
    rustCommon
    // {
      src = lib.cleanSource ./.;
      pname = "devenv-driver";
      version = "0.1.0";
      nativeBuildInputs = [
        pkg-config
        protobuf
        rustPlatform.bindgenHook
      ];
      buildInputs = [
        openssl
        dbus
        nix.libs.nix-expr-c
        nix.libs.nix-store-c
        nix.libs.nix-util-c
        nix.libs.nix-flake-c
        nix.libs.nix-cmd-c
        nix.libs.nix-fetchers-c
        nix.libs.nix-main-c
        boehmgc
        llvmPackages.clang-unwrapped
      ];
      cargoBuildFlags = [
        "--bin"
        "devenv-driver"
      ];
    }
  );

  # Build the backend binary from the Rust code
  devenv-backend = rustPlatform.buildRustPackage (
    rustCommon
    // {
      src = lib.cleanSource ./.;
      pname = "devenv-backend";
      version = "0.1.0";
      buildInputs = [
        openssl
        dbus
      ];
      cargoBuildFlags = [
        "--bin"
        "devenv-backend"
      ];
    }
  );
in
{
  inherit devenv-init devenv-driver devenv-backend;
}
