{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.hermes;
  aiPkgs = self.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  stateDir = "/var/lib/hermes";
  # Host and container must agree so the bind-mounted state keeps its owner.
  hermesId = 2001;
  hermesUser = {
    isSystemUser = true;
    group = "hermes";
    uid = hermesId;
    home = stateDir;
  };
  hermesConfig = pkgs.writers.writeYAML "hermes-config.yaml" cfg.settings;
  # The dashboard judges platforms as configured from its own environment, so
  # both services export the same credentials instead of writing them to .env.
  credentialEnv = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: c: ''
      ${c.env}=$(< "$CREDENTIALS_DIRECTORY/${name}")
      export ${c.env}'') cfg.credentials
  );
  model = {
    default = "gpt-6.1-sol";
    provider = "openai-codex";
    openai_runtime = "auto";
  };
  commonService = {
    User = "hermes";
    Group = "hermes";
    WorkingDirectory = stateDir;
    StateDirectory = "hermes";
    StateDirectoryMode = "0750";
    Restart = "on-failure";
    RestartSec = 30;
    CapabilityBoundingSet = "";
    LockPersonality = true;
    PrivateDevices = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHostname = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    RestrictSUIDSGID = true;
    ImportCredential = lib.attrNames cfg.credentials;
  };
in
{
  imports = [
    ./platforms.nix
    ./dashboard.nix
  ];

  # Feature modules contribute here; the container below consumes the result.
  options.services.hermes = {
    settings = mkOption {
      type = (pkgs.formats.yaml { }).type;
      default = { };
      description = "Contents of Hermes' config.yaml.";
    };
    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Non-secret environment for the gateway and dashboard.";
    };
    packages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Tools installed in the container for Hermes and its terminal tasks.";
    };
    dashboardPort = mkOption {
      type = types.port;
      default = 9119;
      description = "Loopback port of the web dashboard.";
    };
    credentials = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            file = mkOption {
              type = types.str;
              description = "Host path of the secret.";
            };
            env = mkOption {
              type = types.str;
              description = "Environment variable that receives the secret.";
            };
          };
        }
      );
      default = { };
      description = "Secrets loaded into the container and imported by the gateway and dashboard.";
    };
  };

  config = {
    services.hermes = {
      settings = {
        inherit model;
        compression = {
          codex_gpt55_autoraise = true;
          codex_gpt55_autoraise_notice = false;
        };
        # Codex CLI and Claude Code refresh their own logins with single-use
        # refresh tokens; if Hermes borrowed them, each would log the other out.
        auth.adopt_external_logins = false;
        onboarding.profile_build = "off";
        web.search_backend = "searxng";
        terminal.cwd = "${stateDir}/workspace";
      };
      environment = {
        TZ = "Asia/Seoul";
        HOME = stateDir;
        HERMES_HOME = "${stateDir}/.hermes";
        BROWSER_CDP_URL = "http://127.0.0.1:9222";
        SEARXNG_URL = "http://127.0.0.1:8888";
        HERMES_INFERENCE_PROVIDER = model.provider;
        HERMES_INFERENCE_MODEL = model.default;
        HERMES_MODEL = model.default;
      };
      # Both coding CLIs keep their own subscription logins under the state
      # directory (`claude auth login`, `codex login --device-auth`), since they
      # rotate refresh tokens at runtime.
      packages = [
        aiPkgs.hermes-agent
        aiPkgs.claude-code
        aiPkgs.codex
      ];
    };

    users.users.hermes = hermesUser;
    users.groups.hermes.gid = hermesId;
    nix.settings.extra-allowed-users = [ "hermes" ];

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 hermes hermes -"
    ];

    containers.hermes = {
      autoStart = true;

      bindMounts.${stateDir} = {
        hostPath = stateDir;
        isReadOnly = false;
      };

      extraFlags = lib.mapAttrsToList (name: c: "--load-credential=${name}:${c.file}") cfg.credentials;

      config = _: {
        imports = [ ../agent-container.nix ];

        # Hermes runs terminal commands in a login shell, and NixOS' /etc/profile
        # resets PATH there, so tools must live in the system profile rather than
        # only in the units' PATH.
        environment.systemPackages = cfg.packages;

        system.stateVersion = "25.05";

        users.users.hermes = hermesUser;
        users.groups.hermes.gid = hermesId;

        time.timeZone = "Asia/Seoul";

        systemd.tmpfiles.rules = [
          "d ${stateDir} 0750 hermes hermes -"
          "d ${stateDir}/workspace 0750 hermes hermes -"
          "d ${stateDir}/.hermes 0750 hermes hermes -"
          "L+ ${stateDir}/.hermes/config.yaml - - - - ${hermesConfig}"
          "L+ ${stateDir}/.hermes/SOUL.md - - - - ${./SOUL.md}"
        ];

        systemd.services = {
          hermes-gateway = {
            description = "Hermes Agent messaging gateway";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];

            path = [ "/run/current-system/sw" ];
            inherit (cfg) environment;

            serviceConfig = commonService // {
              ExecStart = pkgs.writeShellScript "hermes-gateway" ''
                set -euo pipefail
                ${credentialEnv}
                exec ${lib.getExe aiPkgs.hermes-agent} gateway run
              '';
            };
          };

          hermes-dashboard = {
            description = "Hermes Agent web dashboard";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];

            path = [ "/run/current-system/sw" ];
            inherit (cfg) environment;

            serviceConfig = commonService // {
              ExecStart = pkgs.writeShellScript "hermes-dashboard" ''
                set -euo pipefail
                ${credentialEnv}
                exec ${lib.getExe aiPkgs.hermes-agent} dashboard --host 127.0.0.1 --port ${toString cfg.dashboardPort} --no-open --skip-build
              '';
            };
          };
        };
      };
    };
  };
}
