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
      "devenv-2.0.0" = "sha256-d80K5fyUthiO89Q7L8Gha+7U9q/teAxplulCbws1K5I=";
      "nix-bindings-bindgen-raw-0.1.0" = "sha256-Q+HPIqzOAJ85Af/6ag2IDQ0ssOXatb/AO84pUsPIT98=";
      "secretspec-0.5.0" = "sha256-YKBZcdbR62IxchnGO/Vn5hWac3phvAlE6gGeAhBS50A=";
      "ser_nix-0.1.2" = "sha256-IjTsHTAEBQQ8xyDHW51wufu2mmfmiw+alVjrLrG8bkY=";
      "zitadel-0.0.0-development" = "sha256-Ia2LYUi8VD30kx48pwtVAVN7ko7cOgC7okx6w4bQ1/0=";
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
