{
  lib,
  pkgsStatic,
  rustPlatform,
  pkg-config,
  openssl,
  dbus,
}:

let
  # Common configuration for Rust packages
  rustCommon = {
    doCheck = false;
    doDoc = false;
    cargoLock = {
      lockFile = ./Cargo.lock;
      outputHashes = {
        "axum-typed-websockets-0.6.0" = "sha256-uou03y7v6gtNDrt2Dcb0NcSHNfZqExWBfTYc4sx5MQY=";
        "devenv-1.11.0" = "sha256-fixos/lawsEMOxXROPxsEwgll06yUSyZjclhE8YK1Kk=";
        "ser_nix-0.1.2" = "sha256-CO8jF9ffG1dIk3ehQ7QiNM74xwaNID8YpSlr8zHLDyY=";
        "zitadel-0.0.0-development" = "sha256-Ia2LYUi8VD30kx48pwtVAVN7ko7cOgC7okx6w4bQ1/0=";
      };
    };
    nativeBuildInputs = [
      pkg-config
    ];
    RUSTFLAGS = "--cfg tokio_unstable";
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
      buildInputs = [
        openssl
        dbus
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
