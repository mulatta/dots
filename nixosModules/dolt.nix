{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dolt;
  yaml = pkgs.formats.yaml { };
  cfgDir = "${cfg.dataDir}/.doltcfg";
  serverConfig = yaml.generate "dolt-server.yaml" (
    lib.recursiveUpdate {
      log_level = "info";
      log_format = "text";
      behavior = {
        read_only = false;
        autocommit = true;
        dolt_transaction_commit = false;
      };
      listener = {
        host = "127.0.0.1";
        port = 3306;
      };
      data_dir = cfg.dataDir;
      cfg_dir = cfgDir;
      privilege_file = "${cfgDir}/privileges.db";
      branch_control_file = "${cfgDir}/branch_control.db";
    } cfg.settings
  );

  # Offline `dolt sql` edits the privilege file directly, so no bootstrap server
  # or client is needed. Root changes do not persist offline, and once the file
  # exists root cannot log in over the network; admins are ordinary users here.
  ensureUsersScript = pkgs.writeShellScript "dolt-ensure-users" ''
    set -euo pipefail
    sql=()
    ${lib.concatMapStrings (u: ''
      password=$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/user-${u.name}")
      case "$password" in
        *"'"* | *\\*) echo "dolt: password for ${u.name} contains a quote or backslash" >&2; exit 1 ;;
      esac
      sql+=(
        "CREATE USER IF NOT EXISTS '${u.name}'@'${u.host}' IDENTIFIED BY '$password';"
        "ALTER USER '${u.name}'@'${u.host}' IDENTIFIED BY '$password';"
        "REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${u.name}'@'${u.host}';"
        "GRANT ${u.privileges} ON ${u.on} TO '${u.name}'@'${u.host}'${lib.optionalString u.grantOption " WITH GRANT OPTION"};"
      )
    '') cfg.ensureUsers}
    printf '%s\n' "''${sql[@]}" | ${cfg.package}/bin/dolt \
      --data-dir ${cfg.dataDir} \
      --doltcfg-dir ${cfgDir} \
      --privilege-file ${cfgDir}/privileges.db \
      --branch-control-file ${cfgDir}/branch_control.db \
      sql
  '';
in
{
  # Dolt lacks PostgreSQL peer authentication and MySQL auth_socket. Keep SQL
  # identities and credentials in deployment-specific credential services.
  options.services.dolt = {
    enable = lib.mkEnableOption "Dolt SQL server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.dolt;
      defaultText = lib.literalExpression "pkgs.dolt";
      description = "Dolt package to use.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "dolt";
      description = "User account under which Dolt runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "dolt";
      description = "Group account under which Dolt runs.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/dolt";
      description = "Directory containing Dolt databases and server state.";
    };

    settings = lib.mkOption {
      inherit (yaml) type;
      default = { };
      description = "Dolt sql-server YAML settings.";
    };

    ensureUsers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.strMatching "[A-Za-z0-9_-]+";
              description = "SQL user name.";
            };
            host = lib.mkOption {
              type = lib.types.strMatching "[A-Za-z0-9_.%-]+";
              default = "%";
              description = "Host part of the SQL account.";
            };
            passwordFile = lib.mkOption {
              type = lib.types.path;
              description = "File holding the password, loaded as a systemd credential.";
            };
            privileges = lib.mkOption {
              type = lib.types.str;
              description = "Comma-separated privileges to grant.";
            };
            on = lib.mkOption {
              type = lib.types.str;
              default = "*.*";
              description = "Grant target.";
            };
            grantOption = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether the user may grant its privileges to others.";
            };
          };
        }
      );
      default = [ ];
      description = "SQL accounts whose password and grants are reset on every start.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      home = cfg.dataDir;
    };
    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -" ];

    systemd.services.dolt = {
      description = "Dolt SQL server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStartPre = lib.mkIf (cfg.ensureUsers != [ ]) ensureUsersScript;
        ExecStart = "${cfg.package}/bin/dolt sql-server --config ${serverConfig}";
        LoadCredential = map (u: "user-${u.name}:${u.passwordFile}") cfg.ensureUsers;
        Restart = "on-failure";
        RestartSec = 5;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.dataDir ];
      };
    };
  };
}
