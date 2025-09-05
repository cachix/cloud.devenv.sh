{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.services.zitadel;
  package = pkgs.callPackage ./package.nix { };

  zitadel-config = pkgs.writeText "config.yaml" ''
    Log:
      Level: info

    Port: ${toString cfg.port}

    WebAuthNName:

    ExternalSecure: ${lib.boolToString cfg.externalTLS}
    ExternalDomain: ${cfg.domain}
    ExternalPort: ${toString cfg.externalPort}
    TLS:
      Enabled: false

    Database:
      postgres:
        Host: ${cfg.postgresHost}
        Port: 5432
        Database: ${cfg.database}
        User:
          Username: ${cfg.databaseUser}
          ${lib.optionalString (cfg.databasePassword != null) "Password: ${cfg.databasePassword}"}
          SSL:
            Mode: disable
        Admin:
          Username: ${cfg.databaseUser}
          ${lib.optionalString (cfg.databasePassword != null) "Password: ${cfg.databasePassword}"}
          SSL:
            Mode: disable

    # Use the v2 login UI by default
    # These are per-app controls, but are not available in terraform yet.
    DefaultInstance:
      Features:
        LoginV2:
          Required: false
          # Broken
          # BaseURI: "http://localhost:${toString cfg.loginUIPort}/ui/v2/login"
  '';

  zitadel-steps = pkgs.writeText "steps.yaml" ''
    # https://zitadel.com/docs/self-hosting/manage/configure
    FirstInstance:
      # PATs are not supported by the terraform provider
      MachineKeyPath: ${cfg.devenvCliKeyPath}
      Org:
        Name: ${cfg.organizationName}
        Human:
          # use the loginname root@devenv.localhost
          Username: '${cfg.adminUsername}'
          Password: '${cfg.adminPassword}'
        Machine:
          Machine:
            Username: devenv-cli
            Name: devenv-cli
          MachineKey:
            ExpirationDate: 2100-01-01T00:00:00Z
            Type: 1 # 1 for JSON
  '';

  masterKeyPath = "${config.devenv.state}/zitadel/zitadel-masterkey";
in
{
  options.services.zitadel = {
    enable = lib.mkEnableOption "Zitadel identity management server";

    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      description = "Zitadel package to use";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9500;
      description = "Port for Zitadel server";
    };

    loginUIPort = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = "Port for Zitadel login UI";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "External domain for Zitadel";
    };

    externalPort = lib.mkOption {
      type = lib.types.port;
      default = cfg.port;
      description = "External port for Zitadel (can be different from internal port)";
    };

    externalTLS = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable TLS for external connections";
    };

    database = lib.mkOption {
      type = lib.types.str;
      default = "zitadel";
      description = "Database name for Zitadel";
    };

    databaseUser = lib.mkOption {
      type = lib.types.str;
      default = "domen";
      description = "Database user for Zitadel";
    };

    databasePassword = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "PostgreSQL password for Zitadel database";
    };

    organizationName = lib.mkOption {
      type = lib.types.str;
      default = "devenv";
      description = "Organization name for Zitadel setup";
    };

    adminUsername = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Admin username for Zitadel";
    };

    adminPassword = lib.mkOption {
      type = lib.types.str;
      default = "RootPassword1!";
      description = "Admin password for Zitadel";
    };

    postgresHost = lib.mkOption {
      type = lib.types.str;
      default = config.env.PGHOST;
      description = "PostgreSQL host for Zitadel database";
    };

    devenvCliKeyPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.devenv.state}/zitadel/devenv-cli.token";
      description = "Path to devenv-cli machine key token";
    };

  };

  config = lib.mkIf cfg.enable {
    tasks."app:devenv:zitadel:generate-masterkey" = {
      exec = ''
        mkdir -p ${config.devenv.state}/zitadel
        tr -dc A-Za-z0-9 </dev/urandom | head -c 32 > ${masterKeyPath}
      '';
      status = ''
        test -f ${masterKeyPath}
      '';
      after = [ "devenv:enterShell" ];
    };

    processes.zitadel = {
      exec = ''
        ${cfg.package}/bin/zitadel start-from-init \
          --config ${zitadel-config} \
          --steps ${zitadel-steps} \
          ${
            if config.container.isBuilding then "--masterkeyFromEnv" else "--masterkeyFile ${masterKeyPath}"
          }
      '';
      process-compose = {
        depends_on.postgres.condition = "process_healthy";
        readiness_probe = {
          exec.command = "${cfg.package}/bin/zitadel ready --config ${zitadel-config}";
          initial_delay_seconds = 2;
          period_seconds = 10;
          timeout_seconds = 4;
          success_threshold = 1;
          failure_threshold = 5;
        };

        # https://github.com/F1bonacc1/process-compose#-auto-restart-if-not-healthy
        availability.restart = "on_failure";
      };
    };

    processes.zitadel-login = {
      exec = ''
        docker run --rm --network host \
          -e ZITADEL_API_URL=http://localhost:${toString cfg.port} \
          -e NEXT_PUBLIC_BASE_PATH=/ui/v2/login \
          -e ZITADEL_SERVICE_USER_TOKEN_FILE=/app/login-client.pat \
          -e DEBUG=true \
          -e PORT=${toString cfg.loginUIPort} \
          --mount type=bind,source=${config.devenv.state}/zitadel/login-client.pat,target=/app/login-client.pat \
          ghcr.io/zitadel/zitadel-login:latest
      '';
      process-compose = {
        depends_on.zitadel.condition = "process_healthy";
      };
    };
  };
}
