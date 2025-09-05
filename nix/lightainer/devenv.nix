# Lightweight devenv containers
#
# Adapted from upstream to build containers without the full shell environment.
{
  pkgs,
  lib,
  inputs,
  config,
  ...
}:

{
  config.lib.mkLightainer =
    {
      name,
      tag ? "dev",
      entrypoint ? [
        "/bin/sh"
        "-c"
      ],
      startupCommand ? [ ],
      layers ? [ ],
      registry ? "docker-daemon:",
      defaultCopyArgs ? [ ],
    }:
    let
      nix2containerInput = config.lib.getInput {
        name = "nix2container";
        url = "github:nlewo/nix2container";
        attribute = "containers";
        follows = [ "nixpkgs" ];
      };
      nix2container = nix2containerInput.packages.${pkgs.stdenv.system};

      user = "user";
      group = "user";
      uid = "1000";
      gid = "1000";
      homeDir = "/env";
      bash = pkgs.bashInteractive;

      mkTmp = (
        pkgs.runCommand "devenv-container-tmp" { } ''
          mkdir -p $out/tmp
        ''
      );

      mkEtc = (
        pkgs.runCommand "devenv-container-etc" { } ''
          mkdir -p $out/etc/pam.d

          echo "root:x:0:0:System administrator:/root:${bash}" > \
                $out/etc/passwd
          echo "${user}:x:${uid}:${gid}::${homeDir}:${bash}" >> \
                $out/etc/passwd

          echo "root:!x:::::::" > $out/etc/shadow
          echo "${user}:!x:::::::" >> $out/etc/shadow

          echo "root:x:0:" > $out/etc/group
          echo "${group}:x:${gid}:" >> $out/etc/group

          cat > $out/etc/pam.d/other <<EOF
          account sufficient pam_unix.so
          auth sufficient pam_rootok.so
          password requisite pam_unix.so nullok sha512
          session required pam_unix.so
          EOF

          touch $out/etc/login.defs
        ''
      );

      derivation = nix2container.nix2container.buildImage {
        inherit name tag;
        initializeNixDatabase = false;
        nixUid = lib.toInt uid;
        nixGid = lib.toInt gid;

        copyToRoot = [
          (pkgs.buildEnv {
            name = "devenv-container-root";
            paths = [
              pkgs.coreutils-full
              pkgs.bashInteractive
              pkgs.su
              pkgs.sudo
              pkgs.dockerTools.usrBinEnv
              pkgs.tini
            ];
            pathsToLink = [
              "/bin"
              "/usr/bin"
            ];
          })
          mkEtc
          mkTmp
        ];

        layers = builtins.foldl' (
          layers: layer:
          layers
          ++ [
            (nix2container.nix2container.buildLayer (layer // { inherit layers; }))
          ]
        ) [ ] layers;

        perms = [
          {
            path = mkTmp;
            regex = "/tmp";
            mode = "1777";
            uid = 0;
            gid = 0;
            uname = "root";
            gname = "root";
          }
        ];

        config = {
          Entrypoint = entrypoint;
          User = "${user}";
          WorkingDir = "${homeDir}";
          Env = [
            "HOME=${homeDir}"
            "USER=${user}"
          ];
          Cmd = startupCommand;
        };
      };
    in
    {
      inherit name derivation;
    };
}
