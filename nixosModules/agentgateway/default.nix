{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.services.agentgateway;
  format = pkgs.formats.yaml { };

  credentialsDir = "/run/credentials/agentgateway.service";

  # Validated at build time so a bad route fails the deploy, not the running gateway.
  # Validation opens referenced files, so credentials are swapped for placeholders.
  configFile =
    pkgs.runCommand "agentgateway.yaml"
      {
        config = format.generate "agentgateway-unchecked.yaml" cfg.settings;
        credentialNames = lib.attrNames cfg.credentials;
      }
      ''
        mkdir credentials
        for name in $credentialNames; do
          echo placeholder > "credentials/$name"
        done
        sed "s|${credentialsDir}/|$PWD/credentials/|g" "$config" > check.yaml
        ${cfg.package}/bin/agentgateway --validate-only --file check.yaml
        cp "$config" "$out"
      '';
in
{
  options.services.agentgateway = {
    enable = mkEnableOption "agentgateway, a gateway for LLM, MCP, and A2A traffic";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../packages/agentgateway { };
      defaultText = lib.literalExpression "pkgs.agentgateway";
      description = "agentgateway package to run.";
    };

    settings = mkOption {
      inherit (format) type;
      default = { };
      description = ''
        agentgateway configuration, written to YAML as-is. See the upstream
        `schema/config.md` for the available fields. Reference secrets by file
        through {option}`services.agentgateway.credentials` instead of inlining them.
      '';
    };

    credentials = mkOption {
      type = types.attrsOf types.path;
      default = { };
      example = lib.literalExpression ''
        { deepseek = config.clan.core.vars.generators.agentgateway.files.deepseek-api-key.path; }
      '';
      description = ''
        Secret files passed with systemd `LoadCredential`. Each one is readable by the
        gateway at `/run/credentials/agentgateway.service/<name>`, for example from
        `llm.models[].params.apiKey.file`.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.agentgateway = {
      description = "agentgateway";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/agentgateway --file ${configFile}";
        DynamicUser = true;
        LoadCredential = mapAttrsToList (name: path: "${name}:${path}") cfg.credentials;
        Restart = "on-failure";
        RestartSec = 5;

        CapabilityBoundingSet = "";
        LockPersonality = true;
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
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        UMask = "0077";
      };
    };
  };
}
