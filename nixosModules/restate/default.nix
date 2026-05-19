{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.restate;
  toml = pkgs.formats.toml { };

  defaultSettings = {
    "base-dir" = cfg.dataDir;
    "bind-address" = cfg.bindAddress;

    admin."bind-address" = cfg.adminBindAddress;
    ingress."bind-address" = cfg.ingressBindAddress;
  };

  configFile = toml.generate "restate.toml" (lib.recursiveUpdate defaultSettings cfg.settings);
in
{
  options.services.restate = {
    enable = lib.mkEnableOption "Restate durable execution server";

    package = lib.mkPackageOption pkgs "restate" { };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/restate";
      description = "Directory where Restate stores RocksDB data and node state.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:5122";
      description = "Address for Restate internal node-to-node communication.";
    };

    ingressBindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8080";
      description = "Address for Restate HTTP ingress.";
    };

    adminBindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:9070";
      description = "Address for Restate admin API and Web UI.";
    };

    settings = lib.mkOption {
      type = toml.type;
      default = { };
      example = lib.literalExpression ''
        {
          cluster-name = "opencrow";
          disable-telemetry = true;
          rocksdb-total-memory-size = "1GiB";
        }
      '';
      description = ''
        Restate configuration merged into the generated TOML file. Values here
        override module defaults such as `base-dir` and listener bind addresses.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.restate = {
      isSystemUser = true;
      group = "restate";
      home = cfg.dataDir;
    };
    users.groups.restate = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 restate restate -"
    ];

    systemd.services.restate = {
      description = "Restate durable execution server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      unitConfig.RequiresMountsFor = [ cfg.dataDir ];

      environment.RESTATE_CONFIG = configFile;

      serviceConfig = {
        ExecStart = "${lib.getExe' cfg.package "restate-server"}";
        User = "restate";
        Group = "restate";
        WorkingDirectory = cfg.dataDir;
        ReadWritePaths = [ cfg.dataDir ];
        Restart = "always";
        RestartSec = "5s";

        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
      }
      // lib.optionalAttrs (cfg.dataDir == "/var/lib/restate") {
        StateDirectory = "restate";
        StateDirectoryMode = "0750";
      };
    };
  };
}
