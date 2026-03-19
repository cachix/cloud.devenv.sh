{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  overlays = [ inputs.rust-overlay.overlays.default ];

  dotenv.enable = true;

  env = {
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
    inputs.nix.packages.${pkgs.system}.nix
    # nix C libs for nix-bindings-rust
    inputs.nix.packages.${pkgs.system}.nix-expr-c
    inputs.nix.packages.${pkgs.system}.nix-store-c
    inputs.nix.packages.${pkgs.system}.nix-util-c
    inputs.nix.packages.${pkgs.system}.nix-flake-c
    inputs.nix.packages.${pkgs.system}.nix-cmd-c
    inputs.nix.packages.${pkgs.system}.nix-fetchers-c
    inputs.nix.packages.${pkgs.system}.nix-main-c
    pkgs.boehmgc
    pkgs.rustPlatform.bindgenHook
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
    inputs.crate2nix.packages.${pkgs.system}.default
  ];

  languages = {
    rust = {
      enable = true;
      rustflags = "--cfg tokio_unstable --cfg tracing_unstable";
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

  tasks."db:migrate" = {
    exec = "cargo run -p devenv-backend migrate";
    after = [ "devenv:processes:postgres" ];
    before = [ "devenv:processes:backend" ];
  };

  processes = {
    backend = {
      exec = ''
        export PORT=${toString config.processes.backend.ports.http.value}
        cargo watch -w backend -w oauth-kit -x "run -p devenv-backend serve"
      '';
      ports.http.allocate = 8080;
      after = [ "devenv:processes:postgres" ];
      ready.http.get = {
        host = "127.0.0.1";
        port = config.processes.backend.ports.http.value;
        path = "/metrics";
      };
    };
    frontend = {
      exec = "cd frontend && elm-land server";
      after = [ "devenv:processes:backend" ];
      env.PORT = toString config.processes.frontend.ports.http.value;
      ports.http.allocate = 1234;
      ready.http.get = {
        host = "127.0.0.1";
        port = config.processes.frontend.ports.http.value;
        path = "/";
      };
    };
    runner.exec = ''
      cargo watch -w runner -x "build -p devenv-runner --bin devenv-runner" -s "${lib.optionalString pkgs.stdenv.isDarwin "codesign --force --entitlements runner/resources/runner.entitlements --sign - target/debug/devenv-runner && "}target/debug/devenv-runner --host ws://127.0.0.1:${toString config.processes.backend.ports.http.value}"
    '';
    generate-elm.exec = ''
      cargo watch -w backend -x "run -p devenv-backend generate-elm"
    '';
    logger.exec = ''
      cargo watch -w logger -x "run -p devenv-logger --bin server"
    '';
  };

  files."frontend/elm-land.json".json = {
    app = {
      elm = {
        development = {
          debugger = true;
        };
        production = {
          debugger = false;
        };
      };
      env = [
        "BASE_URL"
      ];
      html = {
        attributes = {
          html = {
            lang = "en";
          };
          head = { };
        };
        title = "Devenv Cloud";
        meta = [
          { charset = "UTF-8"; }
          {
            http-equiv = "X-UA-Compatible";
            content = "IE=edge";
          }
          {
            name = "viewport";
            content = "width=device-width, initial-scale=1.0";
          }
        ];
        link = [
          {
            rel = "icon";
            type = "image/x-icon";
            href = "/favicon.svg";
          }
          {
            rel = "stylesheet";
            href = "https://fonts.googleapis.com/css2?family=Mulish:wght@100;200;300;400;500;600;700;800;900;1000&display=swap";
          }
        ];
        script = [
          {
            type = "text/javascript";
            innerHTML = ''
              // Immediately set theme on page load to prevent flash
              (function() {
                var savedTheme = localStorage.getItem('theme');
                var theme = savedTheme ? JSON.parse(savedTheme) :
                    (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');

                if (theme === 'dark') {
                  document.documentElement.classList.add('dark');
                }
              })();'';
          }
        ];
      };
      router = {
        useHashRouting = false;
      };
      proxy = {
        "/api" = "http://localhost:${toString config.processes.backend.ports.http.value}";
      };
    };
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
  };

  git-hooks = {
    excludes = [
      "frontend/generated-api"
      "frontend/elm-srcs.nix"
      "Cargo.nix"
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
    "devenv:crate2nix" = {
      exec = "crate2nix generate";
      execIfModified = [ "Cargo.lock" ];
      before = [ "devenv:enterShell" ];
    };
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
      nixPkg = inputs.nix.packages.${pkgs.system}.nix;
      rustToolchain = pkgs.rust-bin.stable.latest.default;
      backendPackages = pkgs.callPackage ./package.nix {
        nix = nixPkg;
        rustc = rustToolchain;
        cargo = rustToolchain;
      };
      frontendPackage = pkgs.callPackage ./frontend/package.nix {
        inherit (config.env) BASE_URL;
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

}
