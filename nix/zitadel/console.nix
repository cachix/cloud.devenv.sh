{
  generateProtobufCode,
  version,
  zitadelRepo,
}:

{
  stdenv,
  lib,
  pnpm,
  nodejs,

  grpc-gateway,
  protoc-gen-connect-go,
  protoc-gen-grpc-web,

  pkg-config,
  protobuf_27,
  fetchFromGitHub,
  abseil-cpp_202407,

  buf,
}:

let
  # Fix protobuf_29 builds. This is fixed in nixpkgs-unstable.
  protobuf = protobuf_27.override {
    abseil-cpp = abseil-cpp_202407;
  };

  # Build our own protoc-gen-js to get a working zitadel on macOS.
  # The upstream bazel build is broken.
  protoc-gen-js-custom = stdenv.mkDerivation (finalAttrs: {
    pname = "protoc-gen-js";
    version = "3.21.4";

    src = fetchFromGitHub {
      owner = "protocolbuffers";
      repo = "protobuf-javascript";
      rev = "v${finalAttrs.version}";
      hash = "sha256-eIOtVRnHv2oz4xuVc4aL6JmhpvlODQjXHt1eJHsjnLg=";
    };

    nativeBuildInputs = [
      pkg-config
      stdenv.cc
    ];

    buildInputs = [
      protobuf
      protobuf.passthru.abseil-cpp
    ];

    buildPhase = ''
      runHook preBuild

      $CXX -std=c++17 \
        -I. \
        $(pkg-config --cflags protobuf) \
        generator/*.cc \
        -o protoc-gen-js \
        $(pkg-config --libs protobuf) \
        -lprotoc

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -Dm755 protoc-gen-js $out/bin/protoc-gen-js

      runHook postInstall
    '';
  });

  consoleProtobufGenerated = generateProtobufCode {
    pname = "zitadel-console";
    inherit version;
    nativeBuildInputs = [
      grpc-gateway
      protoc-gen-connect-go
      protoc-gen-grpc-web
      protoc-gen-js-custom
    ];
    workDir = "console";
    bufArgs = "../proto --include-imports --include-wkt";
    outputPath = "src/app/proto";
    hash = "sha256-2wIOIbfl2kI51HoXrCqiTI3AVAArHadU8iPxQUojKyo=";
  };

  zitadelProtobufGenerated = generateProtobufCode {
    pname = "zitadel-proto";
    inherit version;
    workDir = "packages/zitadel-proto";
    bufArgs = "../../proto";
    outputPath = ".";
    hash = "sha256-HZ3zSdYY4uzDEe73MRnwy2hXSsu8+IEw1hUsBxk/Hu0=";
  };

  client = stdenv.mkDerivation (finalAttrs: {
    pname = "zitadel-client";
    inherit version;

    src = zitadelRepo;
    pnpmDeps = pnpm.fetchDeps {
      inherit (finalAttrs) pname version src;
      fetcherVersion = 2;
      hash = "sha256-67W35bs00ZTTy5z3eXc9c1I9Qi1CsfU22/BXAx2Gbp4=";
    };

    pnpmWorkspaces = [
      "@zitadel/proto"
      "@zitadel/client"
    ];

    nativeBuildInputs = [
      pnpm.configHook
      nodejs
      buf
    ];

    preBuild = ''
      cp -r ${zitadelProtobufGenerated}/{cjs,es,types} packages/zitadel-proto
    '';

    buildPhase = ''
      runHook preBuild
      pnpm --filter=@zitadel/client run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -r packages/zitadel-client/dist "$out"
      runHook postInstall
    '';
  });
in
stdenv.mkDerivation (finalAttrs: {
  pname = "zitadel-console";
  inherit version;

  src = zitadelRepo;

  pnpmDeps = pnpm.fetchDeps {
    inherit (finalAttrs) pname version src;
    fetcherVersion = 2;
    hash = "sha256-67W35bs00ZTTy5z3eXc9c1I9Qi1CsfU22/BXAx2Gbp4=";
  };

  pnpmWorkspaces = [
    "@zitadel/proto"
    "@zitadel/client"
    "console"
  ];

  nativeBuildInputs = [
    pnpm.configHook
    nodejs
    buf
  ];

  # Build both v1 and v2 APIs, as well as the client
  preBuild = ''
    cp -r ${consoleProtobufGenerated} console/src/app/proto
    cp -r ${zitadelProtobufGenerated}/{cjs,es,types} packages/zitadel-proto
    cp -r ${client} packages/zitadel-client/dist
  '';

  buildPhase = ''
    runHook preBuild
    pnpm --filter=console build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -r console/dist/console "$out"
    runHook postInstall
  '';
})
