{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mapAttrsToList
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.services.agentgateway;
  format = pkgs.formats.yaml { };

  credentialsDir = "/run/credentials/agentgateway.service";
  runtimeDir = "/run/agentgateway";
  stateDir = "/var/lib/agentgateway";

  # Validated at build time so a bad route fails the deploy, not the running gateway.
  # Validation opens referenced paths, so credentials and runtime paths are swapped for local ones.
  configFile =
    pkgs.runCommand "agentgateway.yaml"
      {
        config = format.generate "agentgateway-unchecked.yaml" cfg.settings;
        credentialNames = lib.attrNames cfg.credentials;
      }
      ''
        mkdir credentials state run
        for name in $credentialNames; do
          echo placeholder > "credentials/$name"
        done
        sed -e "s|${credentialsDir}/|$PWD/credentials/|g" \
          -e "s|${stateDir}|$PWD/state|g" \
          -e "s|${runtimeDir}|$PWD/run|g" \
          "$config" > check.yaml
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
    services.agentgateway.settings.config = {
      # The admin API can shut the gateway down and has no auth, so keep it off TCP
      # where any local process (or agent) could reach it; ssh -L can still forward it.
      adminAddr = mkDefault "unix:${runtimeDir}/admin.sock";
      # The config file is in the Nix store; UI edits would fail or be lost on deploy.
      storage.mode = mkDefault "readOnly";
      # Budgets only survive restarts when usage is persisted.
      database.url = mkDefault "sqlite://${stateDir}/agentgateway.db";
      # Both default to every interface; nothing scrapes metrics and systemd tracks liveness.
      statsAddr = mkDefault "off";
      readinessAddr = mkDefault "off";
    };
    # The database also receives the request log; keep usage and cost, not prompts or replies.
    services.agentgateway.settings.frontendPolicies.logging.database.llm = mkDefault "metadata";

    systemd.services.agentgateway = {
      description = "agentgateway";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/agentgateway --file ${configFile}";
        DynamicUser = true;
        RuntimeDirectory = "agentgateway";
        StateDirectory = "agentgateway";
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
