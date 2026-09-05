{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  aiPkgs = self.inputs.llm-agents.packages.${system};
  hermesPkg = aiPkgs.hermes-agent;
  stateDir = "/var/lib/hermes";
  gen = config.clan.core.vars.generators.hermes;
  runtimePath = [
    hermesPkg
    "/run/current-system/sw"
  ];
  runtimeEnv = {
    TZ = "Asia/Seoul";
    HOME = stateDir;
    HERMES_HOME = "${stateDir}/.hermes";
    HERMES_INFERENCE_PROVIDER = "openai-codex";
    HERMES_INFERENCE_MODEL = "gpt-5.5";
    HERMES_MODEL = "gpt-5.5";
    SLACK_ALLOWED_USERS = "U04GMC10NNP";
  };
  hermesConfig = pkgs.writers.writeYAML "hermes-config.yaml" {
    model = {
      default = "gpt-5.5";
      provider = "openai-codex";
      openai_runtime = "auto";
    };
    onboarding.profile_build = "off";
    compression = {
      codex_gpt55_autoraise = true;
      codex_gpt55_autoraise_notice = false;
    };
    platforms.slack.home_channel = {
      platform = "slack";
      chat_id = "D04GJGZK4SH";
      name = "Seungwon";
    };
  };
  serviceHardening = {
    CapabilityBoundingSet = "";
    LockPersonality = true;
    PrivateDevices = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHostname = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    RestrictSUIDSGID = true;
    StateDirectoryMode = "0750";
  };
in
{
  clan.core.vars.generators.hermes = {
    files.slack-bot-token.secret = true;
    files.slack-app-token.secret = true;

    prompts.slack-bot-token = {
      description = "Slack bot token (xoxb-…) for the Nero app";
      type = "hidden";
    };
    prompts.slack-app-token = {
      description = "Slack app-level token (xapp-…) with connections:write for Nero";
      type = "hidden";
    };

    script = ''
      cp "$prompts/slack-bot-token" "$out/slack-bot-token"
      cp "$prompts/slack-app-token" "$out/slack-app-token"
    '';
  };

  users.users.hermes = {
    isSystemUser = true;
    group = "hermes";
    uid = 2001;
  };
  users.groups.hermes.gid = 2001;
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

    extraFlags = [
      "--load-credential=slack-bot-token:${gen.files.slack-bot-token.path}"
      "--load-credential=slack-app-token:${gen.files.slack-app-token.path}"
    ];

    config = _: {
      imports = [ ../agent-container.nix ];

      system.stateVersion = "25.05";

      users.users.hermes = {
        isSystemUser = true;
        group = "hermes";
        uid = 2001;
        home = stateDir;
      };
      users.groups.hermes.gid = 2001;

      time.timeZone = "Asia/Seoul";

      systemd.tmpfiles.rules = [
        "d ${stateDir} 0750 hermes hermes -"
        "d ${stateDir}/.hermes 0750 hermes hermes -"
        "L+ ${stateDir}/.hermes/config.yaml - - - - ${hermesConfig}"
        "L+ ${stateDir}/.hermes/SOUL.md - - - - ${./SOUL.md}"
      ];

      systemd.services = {
        hermes-agent = {
          description = "Hermes Agent Slack gateway";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          path = runtimePath;
          environment = runtimeEnv;

          serviceConfig = serviceHardening // {
            User = "hermes";
            Group = "hermes";
            WorkingDirectory = stateDir;
            StateDirectory = "hermes";
            ImportCredential = [
              "slack-bot-token"
              "slack-app-token"
            ];
            Restart = "on-failure";
            RestartSec = 30;
            ExecStart = pkgs.writeShellScript "hermes-gateway" ''
              set -euo pipefail
              SLACK_BOT_TOKEN=$(< "$CREDENTIALS_DIRECTORY/slack-bot-token")
              SLACK_APP_TOKEN=$(< "$CREDENTIALS_DIRECTORY/slack-app-token")
              export SLACK_BOT_TOKEN SLACK_APP_TOKEN
              exec ${lib.getExe hermesPkg} gateway run
            '';
          };
        };

        hermes-dashboard = {
          description = "Hermes Agent web dashboard";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          path = runtimePath;
          environment = runtimeEnv;

          serviceConfig = serviceHardening // {
            User = "hermes";
            Group = "hermes";
            WorkingDirectory = stateDir;
            StateDirectory = "hermes";
            Restart = "on-failure";
            RestartSec = 30;
            ExecStart = pkgs.writeShellScript "hermes-dashboard" ''
              set -euo pipefail
              exec ${lib.getExe hermesPkg} dashboard --host 127.0.0.1 --port 9119 --no-open --skip-build
            '';
          };
        };
      };
    };
  };
}
