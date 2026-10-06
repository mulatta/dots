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
  stateDir = "/var/lib/hermes";
  gen = config.clan.core.vars.generators.hermes;
  buzzIdentity = config.clan.core.vars.generators.hermes-buzz;
  buzzCli = self.inputs.buzz.packages.${system}.buzz-cli;
  buzzOwnerPubkey = self.nixosConfigurations.cask.config.services.buzz-relay.ownerPubkey;
  # Existing general channel; relay/channel membership is provisioned separately.
  buzzChannel = "6fd9e6ce-242e-51ce-b931-7644668b87de";
  runtimePath = [
    buzzCli
    aiPkgs.claude-code
    aiPkgs.codex
    aiPkgs.hermes-agent
    "/run/current-system/sw"
  ];
  hermesSettings = {
    model = {
      default = "gpt-6.1-sol";
      provider = "openai-codex";
      openai_runtime = "auto";
    };
    onboarding.profile_build = "off";
    compression = {
      codex_gpt55_autoraise = true;
      codex_gpt55_autoraise_notice = false;
    };
    gateway.platforms.slack.home_channel = {
      platform = "slack";
      chat_id = "D04GJGZK4SH";
      name = "Seungwon";
    };
    gateway.platforms.buzz = {
      enabled = true;
      extra = {
        relay_url = "https://buzz.mulatta.io";
        cli_path = "${buzzCli}/bin/buzz";
        channels = [ buzzChannel ];
        home_channel = buzzChannel;
        allowed_users = [ buzzOwnerPubkey ];
        allow_all_users = false;
        require_mention = true;
        transport = "auto";
        poll_interval = 10;
      };
    };
    display.platforms.buzz = {
      interim_assistant_messages = false;
      tool_progress = "off";
    };
    terminal.cwd = "${stateDir}/workspaces";
  };
  hermesConfig = pkgs.writers.writeYAML "hermes-config.yaml" hermesSettings;
  runtimeEnv = {
    TZ = "Asia/Seoul";
    HOME = stateDir;
    HERMES_HOME = "${stateDir}/.hermes";
    HERMES_INFERENCE_PROVIDER = hermesSettings.model.provider;
    HERMES_INFERENCE_MODEL = hermesSettings.model.default;
    HERMES_MODEL = hermesSettings.model.default;
    SLACK_ALLOWED_USERS = "U04GMC10NNP";
    BUZZ_RELAY_URL = hermesSettings.gateway.platforms.buzz.extra.relay_url;
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

  # Independent bot identity: never reuse the human owner's or relay's key.
  clan.core.vars.generators.hermes-buzz = {
    files.private-key.secret = true;
    files.public-key.secret = false;
    runtimeInputs = [ pkgs.nak ];
    script = ''
      umask 077
      nak key generate > "$out/private-key"
      nak key public < "$out/private-key" > "$out/public-key"
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
      "--load-credential=buzz-private-key:${buzzIdentity.files.private-key.path}"
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
        "d ${stateDir}/workspaces 0750 hermes hermes -"
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

          serviceConfig = commonService // {
            ImportCredential = [
              "slack-bot-token"
              "slack-app-token"
              "buzz-private-key"
            ];
            ExecStart = pkgs.writeShellScript "hermes-gateway" ''
              set -euo pipefail
              SLACK_BOT_TOKEN=$(< "$CREDENTIALS_DIRECTORY/slack-bot-token")
              SLACK_APP_TOKEN=$(< "$CREDENTIALS_DIRECTORY/slack-app-token")
              BUZZ_PRIVATE_KEY=$(< "$CREDENTIALS_DIRECTORY/buzz-private-key")
              export SLACK_BOT_TOKEN SLACK_APP_TOKEN BUZZ_PRIVATE_KEY
              exec ${lib.getExe aiPkgs.hermes-agent} gateway run
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

          serviceConfig = commonService // {
            ExecStart = pkgs.writeShellScript "hermes-dashboard" ''
              set -euo pipefail
              exec ${lib.getExe aiPkgs.hermes-agent} dashboard --host 127.0.0.1 --port 9119 --no-open --skip-build
            '';
          };
        };
      };
    };
  };
}
