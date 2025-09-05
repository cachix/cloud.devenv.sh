{
  lib,
  buildNpmPackage,
  importNpmLock,
  elmPackages,
  elm-land,
  BASE_URL,
  OAUTH_CLIENT_ID,
  OAUTH_AUDIENCE,
}:

let
  packageJson = builtins.fromJSON (builtins.readFile ./package.json);
in
buildNpmPackage (finalAttrs: {
  pname = "devenv-frontend";
  version = packageJson.version or "dev";

  src = lib.cleanSource ./.;

  env = {
    inherit BASE_URL OAUTH_CLIENT_ID OAUTH_AUDIENCE;
  };

  nativeBuildInputs = [
    elmPackages.elm
    elm-land
  ];

  npmDeps = importNpmLock { npmRoot = finalAttrs.src; };
  npmConfigHook = importNpmLock.npmConfigHook;

  preConfigure = elmPackages.fetchElmDeps {
    elmPackages = import ./elm-srcs.nix;
    elmVersion = "0.19.1";
    registryDat = ./registry.dat;
  };

  buildPhase = ''
    runHook preBuild
    elm-land build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r dist/* $out/
    runHook postInstall
  '';
})
