# Crate overrides for crate2nix build
{
  lib,
  stdenv,
  nix,
  openssl,
  dbus,
  pkg-config,
  llvmPackages,
  boehmgc,
  rustPlatform,
  secretspecToml,
}:

let
  nixLibs = [
    nix.libs.nix-expr-c
    nix.libs.nix-store-c
    nix.libs.nix-util-c
    nix.libs.nix-flake-c
    nix.libs.nix-cmd-c
    nix.libs.nix-fetchers-c
    nix.libs.nix-main-c
    # C++ libraries needed at link time (the C wrappers link against these)
    nix.libs.nix-flake
    nix.libs.nix-cmd
    nix.libs.nix-fetchers
    boehmgc
    llvmPackages.clang-unwrapped
  ];

  nixLibsOverride = attrs: {
    buildInputs = (attrs.buildInputs or [ ]) ++ nixLibs;
    nativeBuildInputs = (attrs.nativeBuildInputs or [ ]) ++ [ pkg-config ];
  };

  rustflagsOverride = attrs: {
    extraRustcOpts = (attrs.extraRustcOpts or [ ]) ++ [
      "--cfg"
      "tokio_unstable"
      "--cfg"
      "tracing_unstable"
    ];
  };
in
{
  # Native C library overrides

  openssl-sys = attrs: {
    buildInputs = (attrs.buildInputs or [ ]) ++ [ openssl ];
    nativeBuildInputs = (attrs.nativeBuildInputs or [ ]) ++ [ pkg-config ];
  };

  libdbus-sys = attrs: {
    buildInputs = (attrs.buildInputs or [ ]) ++ lib.optional stdenv.isLinux dbus;
    nativeBuildInputs = (attrs.nativeBuildInputs or [ ]) ++ [ pkg-config ];
  };

  # nix-bindings crates need nix C libs and bindgen

  nix-bindings-bindgen-raw = attrs: {
    buildInputs = (attrs.buildInputs or [ ]) ++ nixLibs;
    nativeBuildInputs = (attrs.nativeBuildInputs or [ ]) ++ [
      pkg-config
      rustPlatform.bindgenHook
    ];
    # nix C headers use C23 [[deprecated(...)]] syntax which requires -std=c2x.
    # bindgenHook appends $NIX_CFLAGS_COMPILE to BINDGEN_EXTRA_CLANG_ARGS.
    NIX_CFLAGS_COMPILE = "-std=c2x";
  };

  nix-bindings-util = nixLibsOverride;
  nix-bindings-store = nixLibsOverride;
  nix-bindings-expr = nixLibsOverride;
  nix-bindings-flake = nixLibsOverride;
  nix-bindings-fetchers = nixLibsOverride;
  nix-cmd = nixLibsOverride;

  devenv-nix-backend = attrs: {
    buildInputs = (attrs.buildInputs or [ ]) ++ nixLibs;
    nativeBuildInputs = (attrs.nativeBuildInputs or [ ]) ++ [
      pkg-config
      rustPlatform.bindgenHook
    ];
    extraRustcOpts = (attrs.extraRustcOpts or [ ]) ++ [
      "--cfg"
      "tokio_unstable"
      "--cfg"
      "tracing_unstable"
    ];
  };

  # Workspace crates need tokio_unstable and tracing_unstable cfg flags

  # devenv-runner binary links nix C++ libs transitively via nix-bindings crates
  devenv-runner = attrs: {
    buildInputs = (attrs.buildInputs or [ ]) ++ [
      nix.libs.nix-flake
      nix.libs.nix-cmd
      nix.libs.nix-fetchers
    ];
    extraRustcOpts = (attrs.extraRustcOpts or [ ]) ++ [
      "--cfg"
      "tokio_unstable"
      "--cfg"
      "tracing_unstable"
    ];
  };

  # devenv-backend uses secretspec_derive::declare_secrets!("../secretspec.toml")
  # which resolves relative to the crate source (/build/source/), so we need
  # secretspec.toml at /build/secretspec.toml
  devenv-backend = attrs: {
    postUnpack = (attrs.postUnpack or "") + ''
      cp ${secretspecToml} secretspec.toml
    '';
    extraRustcOpts = (attrs.extraRustcOpts or [ ]) ++ [
      "--cfg"
      "tokio_unstable"
      "--cfg"
      "tracing_unstable"
    ];
  };
  devenv-logger = rustflagsOverride;
  devenv-init = rustflagsOverride;
  oauth-kit = rustflagsOverride;
  cloud-hypervisor-client = rustflagsOverride;

  # Transitive devenv crates that use tracing with valuable

  devenv = rustflagsOverride;
  devenv-core = rustflagsOverride;
  devenv-eval-cache = rustflagsOverride;
  devenv-tasks = rustflagsOverride;
  devenv-tui = rustflagsOverride;
  devenv-activity = rustflagsOverride;

  # rmcp uses env!("CARGO_CRATE_NAME") at compile time
  rmcp = attrs: {
    CARGO_CRATE_NAME = "rmcp";
  };

  # native-tls build.rs emits cargo:rustc-check-cfg which buildRustCrate
  # converts into an invalid bash variable name (contains colon)
  native-tls = attrs: {
    postInstall = (attrs.postInstall or "") + ''
      if [ -f "$lib/env" ]; then
        grep -v ':RUSTC_CHECK_CFG' "$lib/env" > "$lib/env.tmp" || true
        mv "$lib/env.tmp" "$lib/env"
      fi
    '';
  };

  # aws-lc-sys: fix build sandbox paths and add versioned env vars
  # aws-lc-rs build.rs requires DEP_AWS_LC_{version}_INCLUDE but some
  # buildRustCrate versions only generate DEP_AWS_LC_INCLUDE
  aws-lc-sys = attrs: {
    postInstall =
      let
        version = lib.replaceStrings [ "." ] [ "_" ] (attrs.version or "0.36.0");
      in
      (attrs.postInstall or "")
      + ''
        if [ -f "$lib/env" ]; then
          sed -i "s|/build/.*/target/build/aws-lc-sys\.out|$lib/lib/aws-lc-sys.out|g" "$lib/env"
          if ! grep -q "DEP_AWS_LC_${version}_" "$lib/env"; then
            grep '^export DEP_AWS_LC_[A-Z]' "$lib/env" \
              | sed "s/DEP_AWS_LC_/DEP_AWS_LC_${version}_/" >> "$lib/env"
          fi
        fi
      '';
  };

  # tracing crates need tracing_unstable for valuable support

  tracing = attrs: {
    extraRustcOpts = (attrs.extraRustcOpts or [ ]) ++ [
      "--cfg"
      "tracing_unstable"
    ];
  };

  tracing-core = attrs: {
    extraRustcOpts = (attrs.extraRustcOpts or [ ]) ++ [
      "--cfg"
      "tracing_unstable"
    ];
  };
}
