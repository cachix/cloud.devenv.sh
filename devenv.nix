{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  dotenv.enable = true;

  env = {
    DATABASE_URL = "postgres:///devenv?host=${config.env.PGHOST}";
    RUST_LOG = "info";
  };

  scripts = {
    generate-cloud-hypervisor.exec = ''
      # First fetch the OpenAPI spec
      TEMP_FILE=$(mktemp)
      curl -o "$TEMP_FILE" https://raw.githubusercontent.com/cloud-hypervisor/cloud-hypervisor/master/vmm/src/api/openapi/cloud-hypervisor.yaml

      # Generate Rust client code using openapi-generator-cli
      openapi-generator-cli generate \
        -i "$TEMP_FILE" \
        -g rust \
        --library hyper \
        -o cloud-hypervisor-client

      rm "$TEMP_FILE"
    '';
  };

  packages = [
    pkgs.openssl
    pkgs.cargo-watch
    pkgs.cargo-outdated
    pkgs.cargo-machete
    pkgs.elm-land
    pkgs.diesel-cli
    pkgs.openapi-generator-cli
    pkgs.terraform
    pkgs.bashInteractive
    pkgs.flyctl
    # secretspec
    pkgs.secretspec
    pkgs.dbus
  ];

  languages = {
    rust = {
      enable = true;
    };

    javascript = {
      enable = true;
      directory = "frontend";
      npm.enable = true;
      npm.install.enable = true;
    };
    typescript.enable = true;
    elm.enable = true;
  };

  processes = {
    backend-migrate = {
      exec = ''
        cargo run -p devenv-backend migrate && echo "Migrations completed"
      '';
      process-compose = {
        depends_on.postgres.condition = "process_healthy";
        depends_on.zitadel.condition = "process_healthy";
      };
    };
    backend = {
      exec = ''
        cargo watch -w backend -x "run -p devenv-backend serve"
      '';
      process-compose = {
        depends_on.postgres.condition = "process_healthy";
        depends_on.zitadel.condition = "process_healthy";
        depends_on.backend-migrate.condition = "process_completed_successfully";
        readiness_probe = {
          http_get = {
            host = "127.0.0.1";
            port = 8080;
            path = "/metrics";
          };
        };
      };
    };
    frontend = {
      exec = "cd frontend && elm-land server";
      process-compose = {
        readiness_probe = {
          http_get = {
            host = "127.0.0.1";
            port = 1234;
            path = "/";
          };
        };
      };
    };
    runner.exec = ''
      cargo watch -w runner -x "build -p devenv-runner --bin devenv-runner" -s "${lib.optionalString pkgs.stdenv.isDarwin "codesign --force --entitlements runner/resources/runner.entitlements --sign - target/debug/devenv-runner && "}target/debug/devenv-runner --host ws://127.0.0.1:8080"
    '';
    generate-elm.exec = ''
      cargo watch -w backend -x "run -p devenv-backend generate-elm"
    '';
    logger.exec = ''
      cargo watch -w logger -x "run -p devenv-logger --bin server"
    '';
  };

  services = {
    postgres = {
      enable = true;
      package = pkgs.postgresql_17;
      initialDatabases = [ { name = "devenv"; } ];
      initialScript = ''
        CREATE ROLE domen SUPERUSER CREATEDB LOGIN;
      '';
    };
    tailscale.funnel = {
      enable = true;
      target = "localhost:1234";
    };
    zitadel.enable = true;
  };

  git-hooks = {
    excludes = [
      "frontend/generated-api"
      "frontend/elm-srcs.nix"
    ];
    hooks = {
      rustfmt.enable = true;
      nixfmt-rfc-style.enable = true;
      elm-format.enable = true;
      prettier.enable = true;
      prettier.excludes = [ "cloud-hypervisor-client" ];
      clippy.settings.offline = false;
    };
    settings.rust.cargoManifestPath = "./backend/Cargo.toml";
  };

  enterTest = ''
    cargo check
    cd frontend && elm-land build

    # TODO: configure cloud.devenv.toml
    # wait_for_port 8080 # backend
    # wait_for_port 1234 # frontend
    # wait_for_port 3000 # logger
  '';

  tasks = {
    "frontend:elm2nix" = {
      exec = ''
        cd frontend && elm2nix convert > elm-srcs.nix && elm2nix snapshot
      '';
      execIfModified = [ "frontend/elm.json" ];
      before = [ "devenv:enterShell" ];
    };
  };

  outputs =
    let
      backendPackages = pkgs.callPackage ./package.nix { };
      frontendPackage = pkgs.callPackage ./frontend/package.nix {
        inherit (config.env) BASE_URL OAUTH_AUDIENCE OAUTH_CLIENT_ID;
      };
    in
    {
      inherit (backendPackages) devenv-backend;
      devenv-frontend = frontendPackage;
    };

  containers."backend" = config.lib.mkLightainer {
    name = "devenv-cloud-backend";
    tag = "latest";
    entrypoint = [
      "/bin/secretspec"
      "run"
      "--provider"
      "env"
      "/bin/devenv-backend"
      "serve"
    ];
    layers = [
      {
        copyToRoot = (
          pkgs.buildEnv {
            name = "devenv-backend";
            paths = [
              config.outputs.devenv-backend
              pkgs.secretspec
            ];
            pathsToLink = [ "/bin" ];
          }
        );
        deps = config.outputs.devenv-backend.buildInputs;
      }
      {
        # Copy secretspec config
        copyToRoot = (
          pkgs.buildEnv {
            name = "backend-files";
            paths = [
              (pkgs.writeTextFile {
                name = "secretspec-config";
                text = lib.readFile ./secretspec.toml;
                destination = "/etc/secretspec.toml";
              })
              (pkgs.writeTextFile {
                name = "cloud-devenv-config";
                text = ''
                  base_url = "https://cloud.devenv.sh"

                  [github]
                  app_name="devenv-cloud"
                  app_id = 1897971

                  [zitadel]
                  endpoint = "https://auth.devenv.sh"
                '';
                destination = "/etc/cloud.devenv.toml";
              })
            ];
          }
        );
      }
    ];
  };

  containers."frontend" = config.lib.mkLightainer {
    name = "devenv-cloud-frontend";
    tag = "latest";
    entrypoint = [
      "/bin/caddy"
      "run"
      "--config"
      "/etc/caddy/Caddyfile"
    ];
    layers = [
      {
        copyToRoot = pkgs.buildEnv {
          name = "frontend-root";
          paths = [
            pkgs.caddy
            (pkgs.runCommand "frontend-app" { } ''
              mkdir -p $out/app
              cp -r ${config.outputs.devenv-frontend}/* $out/app/

              mkdir -p $out/etc/caddy
              cat > $out/etc/caddy/Caddyfile << 'EOF'
              :1234 {
                root * /app
                file_server
                try_files {path} /index.html

                @api path /api*
                handle @api {
                  header fly-replay app=devenv-cloud-backend
                  respond "" 307
                }
              }
              EOF
            '')
          ];
          pathsToLink = [
            "/bin"
            "/app"
            "/etc"
          ];
        };
      }
    ];
  };

  containers."zitadel" = config.lib.mkLightainer {
    name = "devenv-cloud-zitadel";
    tag = "latest";
    startupCommand = config.processes.zitadel.exec;
    layers = [
      {
        deps = [
          config.services.zitadel.package
          pkgs.bash
        ];
      }
    ];
  };
}
