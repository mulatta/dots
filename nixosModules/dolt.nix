{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dolt;
  serverConfig = (pkgs.formats.yaml { }).generate "dolt-server.yaml" (
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
      cfg_dir = "${cfg.dataDir}/.doltcfg";
      privilege_file = "${cfg.dataDir}/.doltcfg/privileges.db";
      branch_control_file = "${cfg.dataDir}/.doltcfg/branch_control.db";
    } cfg.settings
  );
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
      type = lib.types.attrs;
      default = { };
      description = "Dolt sql-server YAML settings.";
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
        ExecStart = "${cfg.package}/bin/dolt sql-server --config ${serverConfig}";
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
