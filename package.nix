{
  lib,
  pkgs,
  pkgsStatic,
  pkg-config,
  nix,
  rustc,
  cargo,
  buildRustCrate ? pkgs.buildRustCrate,
  defaultCrateOverrides ? pkgs.defaultCrateOverrides,
}:

let
  # Override buildRustCrate to use the newer rustc from languages.rust
  # The default buildRustCrate uses an older rustc which doesn't support
  # APIs needed by newer crate versions like human_format 1.2.1
  buildRustCrateNew = buildRustCrate.override {
    inherit rustc cargo;
  };

  # crate2nix configuration
  crateConfig = pkgs.callPackage ./crate-config.nix {
    inherit nix;
    secretspecToml = ./secretspec.toml;
  };

  cargoNix = import ./Cargo.nix {
    inherit pkgs lib;
    inherit (pkgs) stdenv;
    buildRustCrateForPkgs = _: buildRustCrateNew;
    defaultCrateOverrides = defaultCrateOverrides // crateConfig;
    release = true;
    extraTargetFlags = {
      tracing_unstable = true;
      tokio_unstable = true;
    };
  };

  # devenv-init needs static linking, which crate2nix doesn't support well.
  # Keep it using buildRustPackage with a narrowed source.
  initSrc = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./init
      ./backend
      ./logger
      ./runner
      ./cloud-hypervisor-client
      ./oauth-kit
    ];
  };

  # devenv-init needs fully static musl binary (runs as VM init process).
  # We use pkgs.makeRustPlatform for vendoring (needs newer cargo for edition 2024)
  # but override buildPhase to target musl, since the cargo build hook hardcodes
  # the platform target and pkgsStatic.makeRustPlatform causes SIGSEGV in build scripts.
  rustcWithMusl = rustc.override {
    targets = [ "x86_64-unknown-linux-musl" ];
  };

  staticRustPlatform = pkgs.makeRustPlatform {
    rustc = rustcWithMusl;
    cargo = rustcWithMusl;
  };

  musl-cc = pkgsStatic.stdenv.cc;

  devenv-init = staticRustPlatform.buildRustPackage {
    pname = "devenv-init";
    version = "0.1.0";
    src = initSrc;
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
    auditable = false;
    doCheck = false;
    doDoc = false;
    nativeBuildInputs = [
      pkg-config
      musl-cc
    ];
    buildInputs = [ pkgsStatic.openssl ];
    # Override build/install phases to target musl directly
    buildPhase = ''
      runHook preBuild
      export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER="${musl-cc}/bin/${musl-cc.targetPrefix}cc"
      export CC_x86_64_unknown_linux_musl="${musl-cc}/bin/${musl-cc.targetPrefix}cc"
      cargo build --release --frozen --target x86_64-unknown-linux-musl --bin init
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      cp target/x86_64-unknown-linux-musl/release/init $out/bin/
      runHook postInstall
    '';
  };
in
{
  inherit devenv-init;
  devenv-driver = cargoNix.workspaceMembers.devenv-runner.build;
  devenv-backend = cargoNix.workspaceMembers.devenv-backend.build;
}
